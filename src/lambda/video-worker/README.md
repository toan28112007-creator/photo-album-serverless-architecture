# Video worker (designed, not deployed)

This is **not a Lambda function** — despite living under `src/lambda/` for
discoverability, this documents the job logic that runs on the EC2 Auto
Scaling Group defined in `infrastructure/terraform/modules/compute`
(gated behind `deploy_video_asg`, currently `false`). See the README's
"What's deployed vs. designed" section and `docs/design-decisions.md`
ADR-1 for why.

## Job logic (as implemented in the bootstrap script)

The actual bootstrap script lives at
`infrastructure/terraform/modules/compute/templates/video-worker-userdata.sh.tpl`.
Each worker instance, once running, does the following in a loop:

```
1. Long-poll the video SQS queue (wait_time_seconds=20).
2. On receiving a message:
   a. Parse the S3 bucket/key from the wrapped SNS/S3 event.
   b. Download the source object from the raw media bucket.
   c. Run `ffprobe -v error -show_entries format=duration -of csv=p=0 <file>`
      — a cheap check, run BEFORE the expensive transcode.
   d. If actual duration > MAX_VIDEO_SECONDS (300s):
        - Mark the DynamoDB record status = "rejected"
        - Delete the SQS message (no retry — this file will never pass)
        - Continue to the next message
   e. Otherwise, transcode with FFmpeg to the target derivative format(s).
   f. Upload the result(s) to the derivatives bucket.
   g. Update the DynamoDB record: status = "completed", derivative keys.
   h. Publish a completion event to EventBridge (frontend refresh signal).
   i. Delete the SQS message.
3. On repeated failure (network error, corrupt file, FFmpeg crash), do NOT
   delete the message — let SQS's redrive policy route it to the DLQ after
   3 receives (see modules/messaging: video_dlq).
```

This two-stage duration check — App API validating the client's declared
duration before issuing a pre-signed URL, and `ffprobe` validating the
actual file here — is why a client that lies about duration still can't
force an expensive full transcode: `ffprobe` runs before FFmpeg's actual
encode pass on every job, regardless of what the client claimed.

## Why this isn't a real Lambda / deployed workload

- Video transcoding routinely exceeds Lambda's 15-minute execution ceiling
  and ~10GB memory limit for longer or higher-resolution source files.
- Validating this end-to-end needs a running EC2 Auto Scaling Group inside
  private VPC subnets, which is impractical to stand up and tear down
  repeatedly within AWS Academy Learner Lab's short, frequently-reset
  sessions.

## What would change to deploy this for real

1. Build a custom AMI (or use a launch template with a user-data install
   step, as currently written) with `ffmpeg` and the AWS CLI baked in.
2. Provide real VPC private subnet IDs, a security group, and an instance
   profile ARN to the `compute` module's variables.
3. Set `deploy_video_asg = true` in `terraform.tfvars`.
4. Replace the placeholder shell loop in the user-data template with the
   full job logic described above (download/ffprobe/transcode/upload/
   update-DynamoDB/publish-EventBridge), likely as a proper systemd
   service rather than an inline bash loop.
