#!/bin/bash
set -euo pipefail
awslocal s3 mb s3://atlas-reports-local
awslocal sns create-topic --name atlas-operations >/dev/null
awslocal sqs create-queue --queue-name atlas-operations-dlq >/dev/null
awslocal sqs create-queue --queue-name atlas-operations --attributes '{"VisibilityTimeout":"60","RedrivePolicy":"{\"deadLetterTargetArn\":\"arn:aws:sqs:us-east-1:000000000000:atlas-operations-dlq\",\"maxReceiveCount\":\"3\"}"}' >/dev/null
awslocal sqs set-queue-attributes --queue-url http://localhost:4566/queue/us-east-1/000000000000/atlas-operations --attributes '{"Policy":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:us-east-1:000000000000:atlas-operations\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"arn:aws:sns:us-east-1:000000000000:atlas-operations\"}}}]}"}'
awslocal sns subscribe --topic-arn arn:aws:sns:us-east-1:000000000000:atlas-operations --protocol sqs --notification-endpoint arn:aws:sqs:us-east-1:000000000000:atlas-operations --attributes RawMessageDelivery=true >/dev/null
touch /tmp/atlas-ready
