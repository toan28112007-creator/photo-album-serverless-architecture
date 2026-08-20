"""
Image processing worker — consumes from the SQS image queue, generates a
thumbnail and a mobile-resized version, writes both to the derivatives
bucket, and updates the metadata record in DynamoDB.

Mirrors Section III-B of the design report ("Media Processing Flow" —
image branch). Runs on Lambda because each job completes in seconds and
fits comfortably within function memory limits (see ADR-1 for why video
does not).
"""

import io
import os
import boto3
from PIL import Image

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

DERIVATIVES_BUCKET = os.environ["DERIVATIVES_BUCKET"]
METADATA_TABLE = os.environ["METADATA_TABLE"]

THUMBNAIL_SIZE = (256, 256)
MOBILE_MAX_DIMENSION = 1080


def lambda_handler(event, context):
    """SQS-triggered handler. Each record is one S3 ObjectCreated event
    (delivered via the SNS -> SQS fan-out in modules/messaging)."""
    table = dynamodb.Table(METADATA_TABLE)

    for record in event["Records"]:
        source_bucket, source_key, media_id = _parse_sns_wrapped_s3_event(record)

        try:
            image_bytes = _download(source_bucket, source_key)

            thumb_key = _derived_key(source_key, "thumb")
            mobile_key = _derived_key(source_key, "mobile")

            _generate_and_upload(image_bytes, THUMBNAIL_SIZE, thumb_key)
            _generate_and_upload(
                image_bytes, (MOBILE_MAX_DIMENSION, MOBILE_MAX_DIMENSION), mobile_key
            )

            table.update_item(
                Key={"media_id": media_id},
                UpdateExpression=(
                    "SET #status = :completed, thumbnail_key = :tk, mobile_key = :mk"
                ),
                ExpressionAttributeNames={"#status": "status"},
                ExpressionAttributeValues={
                    ":completed": "completed",
                    ":tk": thumb_key,
                    ":mk": mobile_key,
                },
            )
        except Exception as exc:  # noqa: BLE001 — let SQS redrive to DLQ
            table.update_item(
                Key={"media_id": media_id},
                UpdateExpression="SET #status = :failed, error_message = :err",
                ExpressionAttributeNames={"#status": "status"},
                ExpressionAttributeValues={":failed": "failed", ":err": str(exc)},
            )
            raise  # re-raise so SQS retries / eventually routes to DLQ

    return {"statusCode": 200}


def _parse_sns_wrapped_s3_event(record):
    """Extract bucket, key, and media_id from an SQS message body that
    wraps an SNS notification wrapping an S3 event notification."""
    import json

    body = json.loads(record["body"])
    s3_event = json.loads(body["Message"])
    s3_record = s3_event["Records"][0]["s3"]

    bucket = s3_record["bucket"]["name"]
    key = s3_record["object"]["key"]
    media_id = key.split("/")[-1].split(".")[0]

    return bucket, key, media_id


def _download(bucket: str, key: str) -> bytes:
    response = s3.get_object(Bucket=bucket, Key=key)
    return response["Body"].read()


def _derived_key(source_key: str, variant: str) -> str:
    base, _, ext = source_key.rpartition(".")
    return f"{base}-{variant}.jpg"


def _generate_and_upload(image_bytes: bytes, max_size: tuple, dest_key: str) -> None:
    with Image.open(io.BytesIO(image_bytes)) as img:
        img = img.convert("RGB")
        img.thumbnail(max_size)

        buffer = io.BytesIO()
        img.save(buffer, format="JPEG", quality=85)
        buffer.seek(0)

        s3.put_object(
            Bucket=DERIVATIVES_BUCKET,
            Key=dest_key,
            Body=buffer,
            ContentType="image/jpeg",
        )
