# SQS — Managed Message Queue

Amazon SQS provides durable, fully managed message queues. In OpenBI,
SQS handles event-driven flows where a producer needs to hand off work
to a consumer without a direct connection between them.

## Where SQS fits in OpenBI

OpenBI has three messaging options:

| Pattern | Tool | When to use |
| --- | --- | --- |
| High-throughput streaming | Kafka / MSK | Ordered events, replay, multiple consumers |
| Simple queue semantics | **SQS** | Fire-and-forget, retries, dead-letter |
| Pub/sub fan-out | SNS | One event, many subscribers |

SQS is the right choice for the "process this event, retry if it
fails" pattern. It is simpler than Kafka, cheaper, and integrated with
every AWS service.

## Queues

Two queues are created:

| Queue | Purpose |
| --- | --- |
| `openbi-events-<suffix>` | Main queue. Producers write; consumers read. |
| `openbi-events-dlq-<suffix>` | Dead-letter queue. Holds messages that failed processing. |

The `<suffix>` is a unique string (typically the AWS account ID) so
queue names don't collide across accounts.

## Design decisions

### Standard queues, not FIFO

Standard SQS queues offer:
- At-least-once delivery
- Best-effort ordering
- High throughput
- Lower cost

FIFO queues offer:
- Exactly-once processing
- Strict ordering
- Lower throughput (300 msg/s per queue, 3000 with batching)
- Higher cost

OpenBI's event flows are order-independent (order created, order
updated, customer notification). Standard queues are the right fit.

**At-least-once** means a consumer might see the same message twice. This
is fine as long as processing is idempotent (which it should be
regardless). Documented in the consumer pattern.

### Long polling by default

`receive_wait_time_seconds = 20`. When a consumer calls
`ReceiveMessage`, SQS holds the connection open for up to 20 seconds
waiting for a message instead of returning immediately.

**Why this matters:** without long polling, an empty queue means the
consumer calls SQS hundreds of times per second, getting nothing back.
With long polling, it calls once every 20 seconds. Same responsiveness,
vastly fewer requests.

This is the single most important SQS operational pattern.

### Visibility timeout: 30 seconds

After a consumer receives a message, SQS hides it from other consumers
for 30 seconds. If the consumer doesn't delete it within that window,
the message becomes visible again — another consumer can pick it up.

30 seconds is the default and works for most synchronous processing.
Longer jobs need a longer timeout (up to 12 hours).

### Dead-letter queue

The main queue has a redrive policy: if a message is received
`max_receive_count` times (default 3) without being deleted, SQS moves
it to the DLQ.

**Why a DLQ:**

- Poison messages don't block the queue forever
- Failed messages are preserved for inspection
- DLQ depth is the signal for "something is wrong"
- A DLQ lets you replay messages after fixing the consumer

**Retention:** DLQ messages are retained for 14 days (vs. 4 days on
the main queue). Longer retention gives time to investigate.

### Encryption

**Default: SSE-SQS.** SQS manages the encryption keys. Free, always
on, no configuration.

**Optional: SSE-KMS.** Set `sqs_managed_sse_enabled = false` and provide
a `kms_master_key_id`. This gives an audit trail (every request logged
to CloudTrail), key rotation control, and fine-grained KMS policies.

OpenBI uses SSE-SQS by default. SSE-KMS is documented as an opt-in.

### Queue policies

Two statements on each queue:

1. **DenyNonAccountAccess** — denies all access to principals outside
   the account. Combined with IAM policies on consumers/producers, this
   keeps the queue private.

2. **DenyInsecureTransport** — denies any request that isn't HTTPS.

## Consumer pattern

The correct consumer loop:

```python
while True:
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=20,
        VisibilityTimeout=30,
    )
    for msg in response.get("Messages", []):
        try:
            process(json.loads(msg["Body"]))
            sqs.delete_message(
                QueueUrl=queue_url,
                ReceiptHandle=msg["ReceiptHandle"],
            )
        except Exception:
            # Do NOT delete. Let it become visible again after the
            # visibility timeout. After max_receive_count attempts, SQS
            # moves it to the DLQ automatically.
            log.exception("processing failed")
Key behaviors:

Delete only after success. If processing raises, don't delete —
the message reappears.

Batch receives (up to 10). Fewer API calls.

Long poll (WaitTimeSeconds=20). Fewer empty receives.

Process is idempotent. At-least-once delivery means duplicates.

Message size limits
SQS messages are limited to 256 KB. For larger payloads, the standard
pattern is:

Store the payload in S3

Send a small SQS message containing the S3 object key

The consumer reads the key, fetches the S3 object, processes it.

This is why S3 and SQS are commonly used together.

Using SQS from Python
python/sqs_operations.py demonstrates:

Sending messages with JSON payloads and message attributes

Long-poll receiving

Deleting after processing

Inspecting queue depth

The DLQ flow (receive-and-abandon → DLQ move)

bash
export OPENBI_SQS_QUEUE_URL=https://sqs.eu-central-1.amazonaws.com/.../openbi-events-...
export OPENBI_SQS_DLQ_URL=https://sqs.eu-central-1.amazonaws.com/.../openbi-events-dlq-...
python python/sqs_operations.py
What maps to GCP
AWS	GCP
SQS standard queue	Cloud Tasks (for task queues) or Pub/Sub (for events)
SQS FIFO queue	Pub/Sub with ordering keys
Dead-letter queue	Dead-letter topics (Pub/Sub)
Visibility timeout	Ack deadline (Pub/Sub)
Long polling	Streaming pull (Pub/Sub)
Message attributes	Message attributes
Server-side encryption	Default encryption / CMEK
What transfers directly:

The producer/consumer decoupling pattern

At-least-once delivery and idempotent processing

Dead-letter queue for poison messages

Long polling / streaming pull for efficient consumption

Message size limits and the S3-offload pattern

What does not transfer:

Queue URL format

The exact SDK (boto3 vs google-cloud-pubsub)

Visibility timeout semantics (Pub/Sub uses ack deadlines, similar but
not identical)

The ReceiptHandle concept (Pub/Sub uses ack IDs)

Verification status
Not verified against real AWS. The Terraform module is statically
validated. The Python script is correct as written but requires real
queue URLs to run. See verification.md.
