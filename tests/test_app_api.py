"""
Unit tests for the App API Lambda handler, focused on the cost-control
logic described in docs/cost-model.md: the 5-minute video cap and the
3-video-per-account limit, enforced at request time before any pre-signed
URL is issued.

Run with: pytest tests/ (from repo root, with src/lambda/app-api on PYTHONPATH)
"""

import json
import os
import sys
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "lambda", "app-api"))

os.environ.setdefault("RAW_MEDIA_BUCKET", "test-raw-bucket")
os.environ.setdefault("METADATA_TABLE", "test-metadata-table")
os.environ.setdefault("MAX_VIDEO_SECONDS", "300")

import handler  # noqa: E402


def _event(body: dict, user_id: str = "test-user-123"):
    return {
        "routeKey": "POST /uploads",
        "rawPath": "/uploads",
        "requestContext": {
            "http": {"method": "POST"},
            "authorizer": {"jwt": {"claims": {"sub": user_id}}},
        },
        "body": json.dumps(body),
    }


@patch.object(handler.s3, "generate_presigned_url", return_value="https://example.com/presigned")
@patch.object(handler, "dynamodb")
def test_image_upload_succeeds_without_duration_check(mock_dynamodb, _mock_presign):
    mock_table = MagicMock()
    mock_dynamodb.Table.return_value = mock_table

    response = handler.lambda_handler(_event({"content_type": "image/jpeg"}), None)

    assert response["statusCode"] == 201
    mock_table.put_item.assert_called_once()


@patch.object(handler.s3, "generate_presigned_url", return_value="https://example.com/presigned")
@patch.object(handler, "dynamodb")
def test_video_within_cap_succeeds(mock_dynamodb, _mock_presign):
    mock_table = MagicMock()
    mock_table.query.return_value = {"Items": []}  # no prior videos
    mock_dynamodb.Table.return_value = mock_table

    response = handler.lambda_handler(
        _event({"content_type": "video/mp4", "duration_seconds": 250}), None
    )

    assert response["statusCode"] == 201


@patch.object(handler, "dynamodb")
def test_video_over_cap_is_rejected(mock_dynamodb):
    response = handler.lambda_handler(
        _event({"content_type": "video/mp4", "duration_seconds": 400}), None
    )

    body = json.loads(response["body"])
    assert response["statusCode"] == 422
    assert "cap" in body["message"]


@patch.object(handler, "dynamodb")
def test_video_missing_duration_is_rejected(mock_dynamodb):
    response = handler.lambda_handler(_event({"content_type": "video/mp4"}), None)

    assert response["statusCode"] == 400


@patch.object(handler, "dynamodb")
def test_fourth_video_is_rejected_by_account_limit(mock_dynamodb):
    mock_table = MagicMock()
    mock_table.query.return_value = {"Items": [{}, {}, {}]}  # 3 existing videos
    mock_dynamodb.Table.return_value = mock_table

    response = handler.lambda_handler(
        _event({"content_type": "video/mp4", "duration_seconds": 100}), None
    )

    body = json.loads(response["body"])
    assert response["statusCode"] == 422
    assert "limit" in body["message"]
