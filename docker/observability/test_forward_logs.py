import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
import json
import urllib.error
from forward_logs import DeliveryError, Forwarder, NewRelic


def event(id="1", timestamp=1000, message="UserCreatedEvent processado"):
    return dict(eventId=id, timestamp=timestamp, message=message, logStreamName="stream")


class ForwarderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = str(Path(self.tmp.name) / "state.db")
        self.source, self.sink = Mock(), Mock()
        self.source.filter_log_events.return_value = {"events": [event()]}
        self.worker = Forwarder(self.source, self.sink, self.path, "group")

    def tearDown(self):
        self.worker.db.close()
        self.tmp.cleanup()

    def test_failed_delivery_is_retried_after_restart(self):
        self.sink.send.side_effect = DeliveryError("offline")
        with self.assertRaises(DeliveryError):
            self.worker.poll(2000)
        self.worker.db.close()
        self.worker = Forwarder(self.source, self.sink, self.path, "group")
        self.sink.send.side_effect = None
        self.assertEqual(self.worker.poll(2000), 1)
        self.assertEqual(self.sink.send.call_count, 2)

    def test_accepted_events_not_sent_again_after_restart(self):
        self.worker.poll(2000)
        self.worker.db.close()
        self.worker = Forwarder(self.source, self.sink, self.path, "group")
        self.assertEqual(self.worker.poll(2000), 0)
        self.sink.send.assert_called_once()

    def test_empty_page_with_token_and_equal_timestamps(self):
        self.source.filter_log_events.side_effect = [
            {"events": [], "nextToken": "next"},
            {"events": [event(), event("2")]}]
        self.assertEqual(self.worker.poll(2000), 2)
        self.assertEqual(self.source.filter_log_events.call_args.kwargs["nextToken"], "next")

    def test_late_events_and_new_streams_are_found(self):
        self.worker.poll(2000)
        later = event("2", 999)
        later["logStreamName"] = "new-stream"
        self.source.filter_log_events.return_value = {"events": [event(), later]}
        self.assertEqual(self.worker.poll(3000), 1)

    def test_monitoring_payload_is_not_sent_as_plain_log(self):
        self.source.filter_log_events.return_value = {"events": [event(message="NR_LAMBDA_MONITORING"), event("2")]}
        self.assertEqual(self.worker.poll(2000), 1)
        self.assertEqual(self.sink.send.call_args.args[0][0]["eventId"], "2")

    def test_batch_boundary_commits_only_accepted_batch(self):
        self.source.filter_log_events.return_value = {"events": [event(str(i)) for i in range(101)]}
        self.sink.send.side_effect = [None, DeliveryError("offline")]
        with self.assertRaises(DeliveryError):
            self.worker.poll(2000)
        self.sink.send.side_effect = None
        self.assertEqual(self.worker.poll(2000), 1)

    def test_region_and_empty_key_validation(self):
        with self.assertRaises(ValueError):
            NewRelic("", "US")
        with self.assertRaises(ValueError):
            NewRelic("test", "INVALID")

    def test_http_payload_preserves_timestamp_and_service_identity(self):
        sink = NewRelic("test-key", "EU")
        response = Mock(status=202)
        context = Mock()
        context.__enter__ = Mock(return_value=response)
        context.__exit__ = Mock(return_value=False)
        sink.opener = Mock()
        sink.opener.open.return_value = context
        sink.send([event()], "group")
        request = sink.opener.open.call_args.args[0]
        payload = json.loads(request.data)[0]
        self.assertEqual(request.full_url, "https://log-api.eu.newrelic.com/log/v1")
        self.assertEqual(request.get_header("Api-key"), "test-key")
        self.assertEqual(payload["logs"][0]["timestamp"], 1000)
        self.assertEqual(payload["common"]["attributes"]["service.name"], "FCG-NotificationLambda")

    def test_rate_limit_respects_retry_after(self):
        sink = NewRelic("test-key", "US")
        sink.opener = Mock()
        sink.opener.open.side_effect = urllib.error.HTTPError(
            sink.endpoint, 429, "Limited", {"Retry-After": "120"}, None)
        with self.assertRaises(DeliveryError) as raised:
            sink.send([event()], "group")
        self.assertEqual(raised.exception.retry_after, 120)
        self.assertNotIn("test-key", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
