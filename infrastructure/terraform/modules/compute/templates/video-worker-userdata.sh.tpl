#!/bin/bash
# Bootstrap script for a video transcoding worker instance.
# NOT currently applied — see docs/design-decisions.md ADR-1 and README.
#
# Responsibilities mirrored from Section IV-D of the report:
#   1. Long-poll the video SQS queue.
#   2. Run a lightweight ffprobe duration check BEFORE the expensive
#      FFmpeg transcode, rejecting anything over ${max_video_seconds}s.
#   3. Transcode with FFmpeg, write output to the derivatives bucket.
#   4. Update the DynamoDB status record.
#   5. Delete the message on success; let it fall through to the DLQ
#      after max receive count on repeated failure.

set -euo pipefail

yum install -y ffmpeg awscli

cat <<'EOF' > /opt/video-worker.sh
#!/bin/bash
QUEUE_URL="${video_queue_url}"
DERIVATIVES_BUCKET="${derivatives_bucket}"
METADATA_TABLE="${metadata_table}"
MAX_SECONDS="${max_video_seconds}"

while true; do
  MSG=$(aws sqs receive-message --queue-url "$QUEUE_URL" --wait-time-seconds 20 --max-number-of-messages 1)
  # ... parse $MSG, download source object, run:
  #   ffprobe -v error -show_entries format=duration -of csv=p=0 <file>
  # reject (mark DynamoDB status=rejected, delete message) if duration > MAX_SECONDS
  # otherwise transcode with ffmpeg, upload result to $DERIVATIVES_BUCKET,
  # update $METADATA_TABLE status=completed, delete the SQS message.
  sleep 1
done
EOF

chmod +x /opt/video-worker.sh
# systemd unit / supervisor setup omitted — see src/lambda/video-worker
# for the equivalent job logic documented as pseudocode.
