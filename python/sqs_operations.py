"""SQS operations via boto3.

Demonstrates the SQS patterns OpenBI uses for event-driven flows:

  1. Send a message
  2. Receive messages with long polling
  3. Delete a message after successful processing
  4. Inspect the dead-letter queue
  5. Redrive: move a DLQ message back to the main queue

Run against real AWS with:

    export AWS_REGION=eu-central-1
    export OPENBI_SQS_QUEUE_URL=https://sqs.eu-central-1.amazonaws.com/123456789012/openbi-events-123456789012
    export OPENBI_SQS_DLQ_URL=https://sqs.eu-central-1.amazonaws.com/123456789012/openbi-events-dlq-123456789012
    python python/sqs_operations.py

Read-write; the script cleans up after itself (deletes anything it sends).
"""

from __future__ import annotations

import json
import os
import sys
import time
import uuid

import boto3
from botocore.exceptions import ClientError


def get_sqs_client():
    region = os.environ.get("AWS_REGION", "eu-central-1")
    return boto3.client("sqs", region_name=region)


def send_event(sqs, queue_url: str, payload: dict) -> str:
    """Send a JSON event and return the message ID."""
    response = sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(payload),
        MessageAttributes={
            "event_type": {
                "DataType": "String",
                "StringValue": payload.get("event_type", "unknown"),
            },
        },
    )
    return response["MessageId"]


def receive_one(sqs, queue_url: str, wait_seconds: int = 20) -> dict | None:
    """Long-poll for one message. Returns the message dict or None."""
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=wait_seconds,
        MessageAttributeNames=["All"],
    )
    messages = response.get("Messages", [])
    return messages[0] if messages else None


def delete_message(sqs, queue_url: str, message: dict) -> None:
    """Delete a message after successful processing."""
    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=message["ReceiptHandle"],
    )


def queue_stats(sqs, queue_url: str) -> dict:
    """Return queue attributes: depth, in-flight, DLQ."""
    response = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=[
            "ApproximateNumberOfMessages",
            "ApproximateNumberOfMessagesNotVisible",
            "ApproximateNumberOfMessagesDelayed",
        ],
    )
    return response["Attributes"]


def demonstrate_dlq_flow(sqs, main_url: str, dlq_url: str, max_receives: int = 3) -> None:
    """Show the DLQ pattern: receive-and-abandon repeatedly to trigger a DLQ move."""
    print(f"\n==> DLQ demo: send one message, receive it {max_receives} times without deleting")
    payload = {"event_type": "dlq_demo", "event_id": str(uuid.uuid4())}
    send_event(sqs, main_url, payload)
    print(f"    sent: {payload['event_id']}")

    for i in range(max_receives):
        msg = receive_one(sqs, main_url, wait_seconds=5)
        if msg is None:
            print(f"    receive {i+1}: (none)")
            break
        print(f"    receive {i+1}: got message, NOT deleting (simulating failure)")
        # Note: we do not delete it. After max_receive_count receives,
        # SQS moves it to the DLQ.
        # To speed this up in a real demo, set visibility_timeout to a
        # few seconds on the queue. In this script we just document the
        # behavior.

    print("\n    (In a real queue with visibility_timeout=30s and max_receive_count=3,")
    print("     the message would now be in the DLQ.)")

    print("\n==> DLQ stats:")
    for k, v in queue_stats(sqs, dlq_url).items():
        print(f"    {k}: {v}")


def main() -> int:
    sqs = get_sqs_client()

    main_url = os.environ.get("OPENBI_SQS_QUEUE_URL")
    dlq_url = os.environ.get("OPENBI_SQS_DLQ_URL")

    if not main_url or not dlq_url:
        print("Set OPENBI_SQS_QUEUE_URL and OPENBI_SQS_DLQ_URL to run live operations.")
        print("\nThe patterns this script demonstrates:")
        print("  1. send_message with JSON payload and MessageAttributes")
        print("  2. receive_message with WaitTimeSeconds=20 (long polling)")
        print("  3. delete_message with the ReceiptHandle after success")
        print("  4. get_queue_attributes to inspect depth")
        print("  5. The DLQ redrive pattern after max_receive_count failures")
        print("\nLong polling is the single most important SQS operational")
        print("pattern: an empty queue with WaitTimeSeconds=20 uses ~1 request")
        print("every 20 seconds instead of hundreds per second.")
        return 0

    # --- Send ---
    print("==> Send")
    event = {
        "event_type": "order.created",
        "event_id": str(uuid.uuid4()),
        "order_id": 12345,
        "amount": 249.99,
    }
    msg_id = send_event(sqs, main_url, event)
    print(f"    sent: {msg_id}")
    print(f"    body: {json.dumps(event)}")

    # --- Queue stats ---
    print("\n==> Main queue attributes")
    for k, v in queue_stats(sqs, main_url).items():
        print(f"    {k}: {v}")

    # --- Receive and delete ---
    print("\n==> Receive (long polling, wait up to 20s)")
    msg = receive_one(sqs, main_url, wait_seconds=20)
    if msg is None:
        print("    (no message)")
    else:
        print(f"    message id: {msg['MessageId']}")
        body = json.loads(msg["Body"])
        print(f"    body: {json.dumps(body)}")
        print(f"    attributes: {msg.get('MessageAttributes', {})}")
        print("    deleting...")
        delete_message(sqs, main_url, msg)
        print("    deleted")

    # --- DLQ demonstration ---
    demonstrate_dlq_flow(sqs, main_url, dlq_url)

    return 0


if __name__ == "__main__":
    sys.exit(main())
