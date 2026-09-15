FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir boto3==1.40.40 \
    && useradd --uid 10001 --create-home forwarder \
    && mkdir /state && chown forwarder:forwarder /state
COPY forward_logs.py .
USER forwarder
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
CMD ["python", "forward_logs.py"]
