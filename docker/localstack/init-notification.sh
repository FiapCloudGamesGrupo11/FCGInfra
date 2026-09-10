#!/bin/bash

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"
FUNCTION_NAME="fcg-notification"
USER_QUEUE="user-created"
PAYMENT_QUEUE="notification-payment-processed"
USER_DLQ="user-created-dlq"
PAYMENT_DLQ="notification-payment-processed-dlq"
LAMBDA_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/fcg-notification-lambda-role"

echo "Criando recursos locais do FCGNotification..."

awslocal iam create-role \
  --role-name fcg-notification-lambda-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  >/dev/null

awslocal sqs create-queue --queue-name "${USER_DLQ}" >/dev/null
awslocal sqs create-queue --queue-name "${PAYMENT_DLQ}" >/dev/null

USER_DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://sqs.${REGION}.localhost.localstack.cloud:4566/${ACCOUNT_ID}/${USER_DLQ}" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

PAYMENT_DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://sqs.${REGION}.localhost.localstack.cloud:4566/${ACCOUNT_ID}/${PAYMENT_DLQ}" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

awslocal sqs create-queue \
  --queue-name "${USER_QUEUE}" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${USER_DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  >/dev/null

awslocal sqs create-queue \
  --queue-name "${PAYMENT_QUEUE}" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${PAYMENT_DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  >/dev/null

awslocal lambda create-function \
  --function-name "${FUNCTION_NAME}" \
  --runtime dotnet8 \
  --handler NotificationsAPI::NotificationsAPI.Function::FunctionHandler \
  --role "${LAMBDA_ROLE}" \
  --zip-file fileb:///opt/code/fcg-notification.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment "Variables={USER_CREATED_QUEUE=${USER_QUEUE},PAYMENT_PROCESSED_QUEUE=${PAYMENT_QUEUE}}" \
  >/dev/null

awslocal lambda wait function-active-v2 --function-name "${FUNCTION_NAME}"

for QUEUE_NAME in "${USER_QUEUE}" "${PAYMENT_QUEUE}"; do
  QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:${QUEUE_NAME}"

  awslocal lambda create-event-source-mapping \
    --function-name "${FUNCTION_NAME}" \
    --event-source-arn "${QUEUE_ARN}" \
    --batch-size 10 \
    --function-response-types ReportBatchItemFailures \
    >/dev/null
done

echo "FCGNotification pronto: filas SQS e Lambda configuradas."
