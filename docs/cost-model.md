# Cost Model

Source: AWS Pricing Calculator, `ap-southeast-2` (Sydney) region. Figures are
**estimated monthly run-rate at the end of each year**, not cumulative
annual totals.

## Growth assumptions

Starting from a baseline of 5,000 users and doubling every six months:

| Milestone | Users |
|---|---|
| End of Year 1 | 20,000 |
| End of Year 2 | 80,000 |
| End of Year 3 | 320,000 |

Monthly user-behaviour assumptions:
- 5 photos/user (avg. 2 MB each) + 0.5 videos/user (avg. 50 MB each)
- 10 viewing sessions/user, 20 media items requested per session
- Traffic split: 70% Australia, 30% international (drives CloudFront cost)

## Table I — Estimated monthly cost by service

| Service | Year 1 config | Year 1 | Year 2 | Year 3 |
|---|---|---|---|---|
| S3 (raw + derivatives + frontend) | ~700 GB storage; 3.1M PUT/GET requests | $21.50 | $86.00 | $344.00 |
| CloudFront | ~8,000 GB data transfer out; 10M HTTPS requests | $650.00 | $2,600.00 | $10,400.00 |
| API Gateway | 3M requests/month | $3.00 | $12.00 | $48.00 |
| Lambda (App API + image workers) | 10M invocations; 300ms avg; 256MB/128MB | $15.50 | $62.00 | $248.00 |
| DynamoDB | On-demand; 3M WRU + 3M RRU; ~50GB storage | $12.00 | $48.00 | $192.00 |
| SNS & SQS | 5M SNS publishes; 10M SQS requests | $6.50 | $26.00 | $104.00 |
| EC2 ASG (video transcoding) | Baseline 2× t3.medium @ 50% duty | $35.00 | $140.00 | $560.00 |
| Route 53 & WAF | 1 hosted zone, 1M DNS queries; 1 Web ACL, 3 rules | $26.00 | $28.00 | $35.00 |
| Cognito | MAU-based; first 50,000 MAU free | $0.00 | $165.00 | $1,485.00 |
| CloudWatch & CloudTrail | 10 metrics, 5 alarms, 10GB logs | $15.00 | $45.00 | $120.00 |
| **Total (monthly run-rate)** | | **$784.50** | **$3,212.00** | **$13,536.00** |

CloudFormation, EventBridge, and KMS are omitted (combined <$5/month at this
scale). VPC Endpoints for S3/SQS access from EC2 workers add only a small
fixed hourly charge. Amazon Rekognition is a planned future extension (see
README roadmap) and has not been costed.

## Reading the table correctly

Year 2 and Year 3 figures scale the Year 1 usage inputs proportionally to
the projected 4× annual user growth, **with tiered-pricing adjustments
applied where they change the shape of the curve** — most notably Cognito's
free tier of 50,000 MAU, which is why its Year 1 cost is $0.00 despite
every other row scaling linearly with users.

## Resource limits as a cost-control mechanism

Video transcoding on EC2 is the most compute-intensive, costly operation in
the pipeline. Two application-level limits bound its cost during initial
deployment:

- **5-minute cap per video** — enforced twice: the App API validates
  client-reported duration before issuing a pre-signed upload URL (rejecting
  oversized requests before any S3 storage or SQS message is created), and
  the EC2 worker runs a lightweight `ffprobe` duration check as the first
  step of each job — before the expensive FFmpeg transcode — as a defence
  against a client that misreports duration.
- **3 videos per account** — a business policy, not a technical ceiling
  (unlike Lambda's hard 15-minute limit, EC2 has no inherent runtime cap),
  so it can be raised in stages or replaced by a subscription-tiered quota
  without any change to the upload/processing flow.

## Cost vs. benefit

- DynamoDB (on-demand) and Lambda convert CapEx into OpEx — the business
  pays for exact usage, not idle capacity.
- The EC2 ASG is provisioned only when a backlog exists (queue-depth
  scaling), keeping compute utilization in the target 50–60% range instead
  of over-provisioning for peak.
- The dominant cost — CloudFront, ~77% of Year 3 spend — is the direct,
  traceable cost of solving the requirement that drove this redesign: poor
  response times for the ~30% of traffic outside Australia.
