"""
App API — business logic behind API Gateway. Handles album/media metadata
operations and issues pre-signed S3 upload URLs so clients upload directly
to the raw media bucket, bypassing this Lambda entirely for the file
payload itself (see ADR-6).

Also enforces the 5-minute video cap at request time, before any pre-signed
URL is issued — the first of the two enforcement points described in
docs/cost-model.md (the second is the ffprobe check in the video worker).
"""

import json
import os
import uuid

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

RAW_MEDIA_BUCKET = os.environ["RAW_MEDIA_BUCKET"]
METADATA_TABLE = os.environ["METADATA_TABLE"]
MAX_VIDEO_SECONDS = int(os.environ.get("MAX_VIDEO_SECONDS", "300"))
PRESIGNED_URL_EXPIRY_SECONDS = 300


def lambda_handler(event, context):
    route = event.get("routeKey") or f'{event["requestContext"]["http"]["method"]} {event["rawPath"]}'

    if route.endswith("/uploads") and event["requestContext"]["http"]["method"] == "POST":
        return _create_upload(event)

    if route.endswith("/albums") and event["requestContext"]["http"]["method"] == "GET":
        return _list_albums(event)

    return _response(404, {"message": "not found"})


def _create_upload(event):
    """Issue a pre-signed PUT URL for a new upload, after validating the
    client-declared media type/duration against the cost-control limits
    described in docs/cost-model.md."""
    body = json.loads(event.get("body") or "{}")
    content_type = body.get("content_type", "")
    declared_duration_seconds = body.get("duration_seconds")
    user_id = _user_id_from_claims(event)

    is_video = content_type.startswith("video/")

    if is_video:
        if declared_duration_seconds is None:
            return _response(400, {"message": "duration_seconds required for video uploads"})
        if declared_duration_seconds > MAX_VIDEO_SECONDS:
            return _response(
                422,
                {
                    "message": f"video exceeds the {MAX_VIDEO_SECONDS}-second cap",
                    "declared_duration_seconds": declared_duration_seconds,
                },
            )
        if _video_count_for_user(user_id) >= 3:
            return _response(
                422, {"message": "account has reached the 3-video upload limit"}
            )

    media_id = str(uuid.uuid4())
    media_type = "video" if is_video else "image"
    key = f"{user_id}/{media_id}.{_extension_for(content_type)}"

    presigned_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": RAW_MEDIA_BUCKET, "Key": key, "ContentType": content_type},
        ExpiresIn=PRESIGNED_URL_EXPIRY_SECONDS,
    )

    table = dynamodb.Table(METADATA_TABLE)
    table.put_item(
        Item={
            "media_id": media_id,
            "owner": user_id,
            "media_type": media_type,
            "s3_key": key,
            "status": "pending_upload",
        }
    )

    return _response(
        201,
        {
            "media_id": media_id,
            "upload_url": presigned_url,
            "expires_in": PRESIGNED_URL_EXPIRY_SECONDS,
        },
    )


def _list_albums(event):
    user_id = _user_id_from_claims(event)
    table = dynamodb.Table(METADATA_TABLE)

    response = table.query(
        IndexName="owner-index",  # see infrastructure notes: add a GSI on `owner` before deploying this route
        KeyConditionExpression="owner = :owner",
        ExpressionAttributeValues={":owner": user_id},
    )
    return _response(200, {"items": response.get("Items", [])})


def _video_count_for_user(user_id: str) -> int:
    table = dynamodb.Table(METADATA_TABLE)
    response = table.query(
        IndexName="owner-index",
        KeyConditionExpression="owner = :owner",
        FilterExpression="media_type = :video",
        ExpressionAttributeValues={":owner": user_id, ":video": "video"},
    )
    return len(response.get("Items", []))


def _user_id_from_claims(event) -> str:
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    return claims["sub"]


def _extension_for(content_type: str) -> str:
    return {
        "image/jpeg": "jpg",
        "image/png": "png",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
    }.get(content_type, "bin")


def _response(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
