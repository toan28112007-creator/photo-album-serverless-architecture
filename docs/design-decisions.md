# Design Decisions

This document records the significant architectural decisions, in
lightweight ADR (Architecture Decision Record) style, condensed from the
full report's Sections II and IV.

Each entry: **Context → Decision → Alternatives considered → Trade-off accepted**

---

## ADR-1: Compute — API/business logic on Lambda, video transcoding on EC2

**Context.** The original system ran a fixed EC2 fleet at >80% CPU
utilization. Traffic is expected to double every six months for 2–3 years.

**Decision.** Route all request/response and image-processing logic through
API Gateway + Lambda. Run video transcoding on an EC2 Auto Scaling Group
inside private subnets, scaled by SQS queue depth (`ApproximateNumberOfMessagesVisible`)
rather than CPU utilization.

**Alternatives considered.**
- **Lambda for video too** — rejected. Lambda enforces a 15-minute execution
  ceiling and ~10 GB memory limit; longer or higher-resolution source files
  exceed both.
- **AWS MediaConvert / AWS Fargate** — both remain viable serverless
  alternatives to the EC2 pipeline and would require no change to the
  SNS/SQS queue contract if adopted later. Not chosen initially to keep the
  first deployment simpler to reason about and cost against a known
  instance-hour model.

**Trade-off accepted.** EC2 reintroduces exactly the operational burden the
rest of the design avoids — an AMI to patch, an idle baseline of instances
to absorb the first job before scaling reacts, and hourly (not per-millisecond)
billing. This is accepted because it's confined to a single, well-bounded
pipeline: a backlog or failure in video transcoding has no effect on image
processing, and the branch can be swapped for MediaConvert/Fargate later
without touching any other component.

---

## ADR-2: Data — DynamoDB over Aurora/RDS

**Context.** The existing relational database is costly to run continuously
and its strengths (joins, ad-hoc queries) are never used by this workload —
access is a lookup by identifier or a query by owner, storing metadata only
(never media itself).

**Decision.** DynamoDB in on-demand capacity mode.

**Alternatives considered.** Amazon Aurora / RDS — rejected for this
workload because it bills for an always-on instance regardless of traffic,
and its relational features add no value to a key-value access pattern.

**Trade-off accepted.** Loses SQL flexibility (joins, ad-hoc reporting) in
exchange for per-request billing, automatic cross-AZ replication with no
configuration, and single-digit-millisecond lookups at any scale.

---

## ADR-3: API entry point — API Gateway over Application Load Balancer

**Decision.** API Gateway as the managed REST entry point, integrated
directly with the Cognito authorizer and Lambda.

**Alternatives considered.** Application Load Balancer (ALB) — rejected as
primary entry point because it requires a permanently running compute
target behind it (defeating the pay-per-use goal) and doesn't natively
integrate an authorizer against Cognito the way API Gateway does.

**Trade-off accepted.** API Gateway has a per-request cost floor that a
raw ALB doesn't at very high sustained throughput — acceptable at this
project's traffic scale, worth revisiting only at extreme volume.

---

## ADR-4: Infrastructure as Code — CloudFormation (report) / Terraform (this repo)

**Context.** The original report specifies AWS CloudFormation, since it
integrates natively with AWS Amplify comparisons made in Section IV-G and
requires no additional tooling in an AWS-only environment.

**Decision (this repo).** Re-implemented in **Terraform** instead of
CloudFormation for the public portfolio version.

**Reasoning for the deviation.** Terraform is cloud-agnostic and more
common in job descriptions outside AWS-only shops, and its plan/apply
workflow is a better fit for a Learner Lab account whose sessions reset
frequently — `terraform apply` restores the full stack in minutes rather
than re-clicking a console flow. The underlying resource decisions (S3,
SNS/SQS, Lambda, DynamoDB, API Gateway, CloudFront/OAC) are unchanged from
the original report; only the IaC tool differs.

**Alternatives considered.** AWS Amplify — rejected in the original report
because it abstracts away the fine-grained control needed over IAM
policies, VPC placement for the EC2 fleet, and the SNS/SQS fan-out wiring;
Amplify targets simpler, more opinionated application shapes.

---

## ADR-5: Edge — CloudFront + Origin Access Control over public S3

**Decision.** CloudFront serves both the frontend and media derivatives
buckets, with Origin Access Control (OAC) as the only path to their
contents; both buckets are otherwise fully private.

**Alternatives considered.** Public S3 bucket + bucket policy — rejected
because a public bucket remains directly reachable by anyone with the
object URL, bypassing CloudFront's caching, WAF inspection, and access
logging entirely. OAC removes that path: S3 only accepts requests signed
by CloudFront itself.

---

## ADR-6: Upload path — client-to-S3 pre-signed URLs, bypassing compute

**Decision.** The client uploads media directly to the S3 raw bucket using
a pre-signed URL issued by the App API Lambda function, never routing the
file payload itself through API Gateway or Lambda.

**Reasoning.** Routing large media through the compute tier would hit
Lambda's payload-size and execution-duration constraints and would be
strictly slower and more expensive than a direct client→S3 transfer. This
keeps the compute tier scoped to metadata and business logic only.

---

## Quantitative notes (from Section IV-H of the report)

These are the concrete numbers used to justify ADR-1 through ADR-3 in the
original report's comparison tables:

- **Lambda cold start:** typically 100–300ms for a small function on a
  standard runtime, versus near-zero for an already-warm EC2 instance —
  a factor in choosing EC2 for a workload that runs continuously rather
  than in short bursts.
- **Lambda hard limits:** 15-minute maximum execution time; ~10,240 MB
  maximum memory allocation — the specific ceiling that rules Lambda out
  for longer video transcodes.
- **DynamoDB on-demand vs. Aurora:** DynamoDB on-demand has zero fixed
  monthly floor; the smallest viable Aurora instance bills continuously
  regardless of query volume.
- **API Gateway vs. ALB:** API Gateway bills per request with no
  minimum running compute behind it; an ALB requires at least one
  continuously running target to have anything to load-balance to.

For the full reasoning behind each of the four comparison pairs (EC2 vs.
Lambda, Aurora vs. DynamoDB, API Gateway vs. ALB, CloudFormation vs.
Amplify), see Section IV-G/H of [`report.pdf`](report.pdf).
