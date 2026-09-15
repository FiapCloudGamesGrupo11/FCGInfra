"""LocalStack CloudWatch Logs -> New Relic Logs (at-least-once delivery)."""
import json
import logging
import os
from pathlib import Path
import signal
import sqlite3
import threading
import time
import urllib.error
import urllib.request

LOG = logging.getLogger("lambda-log-forwarder")
ENDPOINTS = {
    "US": "https://log-api.newrelic.com/log/v1",
    "EU": "https://log-api.eu.newrelic.com/log/v1",
    "JP": "https://log-api.jp.nr-data.net/log/v1",
}


class DeliveryError(Exception):
    def __init__(self, message, retry_after=30):
        super().__init__(message)
        self.retry_after = retry_after


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # Never forward the ingestion key to a redirected host.


class NewRelic:
    def __init__(self, key, region):
        if not key.strip():
            raise ValueError("Defina NEW_RELIC_LICENSE_KEY para encaminhar os logs.")
        if region not in ENDPOINTS:
            raise ValueError("NEW_RELIC_REGION deve ser US, EU ou JP.")
        self.key, self.endpoint = key, ENDPOINTS[region]
        self.opener = urllib.request.build_opener(NoRedirect())

    def send(self, events, group):
        payload = [{"common": {"attributes": {
            "service.name": "FCG-NotificationLambda",
            "app.name": "FCG-NotificationLambda",
            "environment": "localstack",
            "aws.logGroup": group,
            "aws.lambda.functionName": "fcg-notification",
        }}, "logs": [{"timestamp": e["timestamp"], "message": e["message"],
                      "attributes": {"aws.logStream": e["logStreamName"],
                                     "aws.logEventId": e["eventId"]}} for e in events]}]
        request = urllib.request.Request(self.endpoint,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json", "Api-Key": self.key}, method="POST")
        try:
            with self.opener.open(request, timeout=30) as response:
                if not 200 <= response.status < 300:
                    raise DeliveryError("New Relic retornou HTTP " + str(response.status))
        except urllib.error.HTTPError as error:
            retry = error.headers.get("Retry-After", "30")
            retry = int(retry) if retry.isdigit() else 30
            raise DeliveryError(f"New Relic retornou HTTP {error.code}; lote sera repetido.",
                                min(max(retry, 10), 3600)) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise DeliveryError("Falha de conexao com New Relic; lote sera repetido.") from None


class Forwarder:
    def __init__(self, source, sink, database, group, lookback_hours=24):
        if not 1 <= lookback_hours <= 47:
            raise ValueError("LOOKBACK_HOURS deve ficar entre 1 e 47 (limite de idade do New Relic).")
        self.source, self.sink, self.group = source, sink, group
        self.lookback_ms = lookback_hours * 3600 * 1000
        Path(database).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(database)
        self.db.execute("CREATE TABLE IF NOT EXISTS delivered (id TEXT PRIMARY KEY, timestamp INTEGER NOT NULL)")

    def identity(self, event):
        return json.dumps([self.group, event["logStreamName"], event["eventId"]])

    def flush(self, events):
        if not events:
            return 0
        self.sink.send(events, self.group)
        # Commit only after HTTP acceptance. A crash between these steps can duplicate a batch.
        with self.db:
            self.db.executemany("INSERT OR IGNORE INTO delivered VALUES (?, ?)",
                [(self.identity(e), e["timestamp"]) for e in events])
        LOG.info("New Relic aceitou %d registros da Lambda.", len(events))
        return len(events)

    def poll(self, now_ms=None):
        now_ms = now_ms if now_ms is not None else int(time.time() * 1000)
        start = now_ms - self.lookback_ms
        # Re-scan a bounded window: includes late logs, new streams and LocalStack restarts.
        # eventId deduplication is persistent; pagination tokens are never stored across polls.
        args = {"logGroupName": self.group, "startTime": start, "endTime": now_ms, "limit": 100}
        batch, size, sent = [], 0, 0
        seen = set()
        tokens = set()
        while True:
            page = self.source.filter_log_events(**args)
            for event in page.get("events", []):
                key = self.identity(event)
                if key in seen or self.db.execute("SELECT 1 FROM delivered WHERE id = ?", (key,)).fetchone():
                    continue
                seen.add(key)
                # This encoded APM payload is not a human-readable log or a telemetry integration.
                if "NR_LAMBDA_MONITORING" in event["message"]:
                    continue
                event_size = len(json.dumps(event, ensure_ascii=False).encode("utf-8"))
                if batch and (size + event_size > 500_000 or len(batch) >= 100):
                    sent += self.flush(batch)
                    batch, size = [], 0
                batch.append(event)
                size += event_size
            token = page.get("nextToken")
            if not token:
                break
            if token in tokens:
                raise DeliveryError("LocalStack repetiu o token de paginacao; consulta sera reiniciada.")
            tokens.add(token)
            args["nextToken"] = token
        sent += self.flush(batch)
        with self.db:
            self.db.execute("DELETE FROM delivered WHERE timestamp < ?", (start - 3600_000,))
        return sent


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        sink = NewRelic(os.getenv("NEW_RELIC_LICENSE_KEY", ""), os.getenv("NEW_RELIC_REGION", "US").upper())
        import boto3
        from botocore.config import Config
        source = boto3.client("logs", endpoint_url=os.getenv("AWS_ENDPOINT_URL", "http://localstack:4566"),
            region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
            aws_access_key_id="test", aws_secret_access_key="test",
            config=Config(connect_timeout=5, read_timeout=30, retries={"max_attempts": 2}))
        forwarder = Forwarder(source, sink, os.getenv("STATE_DATABASE", "/state/delivered.db"),
            os.getenv("LOG_GROUP", "/aws/lambda/fcg-notification"), int(os.getenv("LOOKBACK_HOURS", "24")))
        interval = max(1, int(os.getenv("POLL_SECONDS", "15")))
    except (ValueError, sqlite3.Error, OSError) as error:
        LOG.error("Configuracao invalida (%s). Verifique chave, regiao e volume /state.", type(error).__name__)
        return 1
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    LOG.info("Encaminhador iniciado: grupo %s; regiao New Relic %s.", forwarder.group, os.getenv("NEW_RELIC_REGION", "US"))
    try:
        while not stop.is_set():
            wait = interval
            try:
                forwarder.poll()
            except DeliveryError as error:
                LOG.warning("%s", error)
                wait = error.retry_after
            except Exception as error:
                # SDK exceptions can carry request details; never print keys or log contents.
                LOG.warning("Consulta/estado indisponivel (%s); nova tentativa em 30s.", type(error).__name__)
                wait = 30
            stop.wait(wait)
    finally:
        forwarder.db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
