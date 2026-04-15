---
name: review-aws-well-architected
description: "Lightweight Well-Architected Framework review across the five pillars — Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
argument-hint: "[workload name]"
---

# AWS Well-Architected Review (Lite)

Run a focused Well-Architected Framework pass across the five pillars for a single workload. Produces per-pillar RED/YELLOW/GREEN scores grounded in the workload's Terraform or CloudFormation. This skill is strictly **read-only** — it never mutates AWS resources and never runs Terraform `apply`.

## Invocation

The user runs `/review-aws-well-architected [workload name]`. If the workload name is omitted, ask for it. The argument is a logical name — the skill also asks for the IaC paths and the target account/region.

## Execution Steps

Run steps in order. Every pillar checklist item reports one of: **GREEN** (evidence of good practice), **YELLOW** (partial or undocumented), **RED** (clear gap), or **INCONCLUSIVE** (cannot verify from repo). Never invent evidence.

### 1. Scope the Workload

Use AskUserQuestion to collect:

1. Workload name and business tier (critical, tier-2, dev).
2. Terraform or CloudFormation root paths covering the workload.
3. Target AWS account id and region.
4. Whether to perform live read-only checks against the account (requires `aws` and valid credentials) or IaC-only analysis.

If live mode is selected, probe credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

```bash
AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
[ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
"$AUTH" aws
```

If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark live-dependent checks **SKIPPED** with the `detail` field as the reason, fall back to IaC-only, and record the degradation in the report header.

### 2. Run Pillar Checklist — Operational Excellence

1. Does `docs/runbooks/<workload>.md` (or similar) exist? If not, RED.
2. Is there a CI/CD pipeline definition in-repo (`.github/workflows/`, `buildspec.yml`, `.gitlab-ci.yml`)? If not, YELLOW.
3. Do all workload resources declare an `Owner`, `Team`, or `CostCenter` tag? Cross-reference with `review-aws-tagging` when available.
4. Are there CloudWatch alarms for the workload? `aws cloudwatch describe-alarms --alarm-name-prefix <workload>` in live mode, or `aws_cloudwatch_metric_alarm` in IaC.
5. Is there a change approval trail (CODEOWNERS, required reviewers)?
6. Are there documented on-call and escalation paths?

### 3. Run Pillar Checklist — Security

1. Customer-managed KMS keys used for sensitive stores (RDS, S3 with sensitive data, Secrets Manager)? `aws_kms_key` in IaC, or `aws kms list-keys` + `aws kms describe-key` live.
2. VPC endpoints for S3, DynamoDB, STS, KMS, Secrets Manager? Prevents traffic via public endpoints.
3. Security group sprawl: count rules with `0.0.0.0/0` ingress on non-public-facing resources. Any hit is RED.
4. GuardDuty enabled in the region? `aws guardduty list-detectors`. Macie for S3 content? `aws macie2 get-macie-session`.
5. AWS Config recording enabled? `aws configservice describe-configuration-recorders`.
6. Secrets stored in Secrets Manager or SSM SecureString — not in plain SSM parameters or environment variables.
7. Public S3 buckets? `aws s3api get-bucket-policy-status` and `aws s3api get-public-access-block` on each bucket.
8. Defer IAM depth to `review-aws-iam` — link rather than duplicate.

### 4. Run Pillar Checklist — Reliability

1. Multi-AZ for stateful resources? RDS `MultiAZ: true`, ElastiCache replication groups, EFS lifecycle.
2. Auto Scaling for compute? `aws_autoscaling_group`, `aws_ecs_service` with desired count > 1, EKS node groups with `min_size` > 1.
3. Health checks on all load balancer target groups? `HealthCheckPath`, `HealthCheckProtocol`.
4. Backup plans covering every stateful resource? `aws backup list-backup-plans` in live mode.
5. Chaos or failover exercise evidence in the repo (GameDay log, failover runbook)?
6. Defer disaster-recovery depth to `review-disaster-recovery` — link rather than duplicate.

### 5. Run Pillar Checklist — Performance Efficiency

1. Instance families appropriate for the workload (for example, `t3` for burst, `m6i` for steady compute, `r6i` for memory)? Flag `t2`/`t3.nano` on production and oversized families on light workloads.
2. Caching layer present where latency matters — ElastiCache, CloudFront, DAX?
3. Connection pooling for RDS (RDS Proxy, application-side pool declared)?
4. CloudFront in front of static assets and API Gateway where applicable?
5. Right-sizing evidence — Compute Optimizer findings if accessible: `aws compute-optimizer get-ec2-instance-recommendations`.

### 6. Run Pillar Checklist — Cost Optimization

1. Savings Plans or Reserved Instance coverage? `aws ce get-savings-plans-coverage` or `aws ce get-reservation-coverage`.
2. S3 lifecycle policies on buckets with long-lived data? `aws_s3_bucket_lifecycle_configuration` in IaC or `aws s3api get-bucket-lifecycle-configuration`.
3. NAT Gateway egress — centralized via Transit Gateway or per-VPC? Multiple NATs across AZs in dev accounts.
4. Idle resources: orphaned EBS volumes, unattached EIPs, load balancers with no registered targets.
5. Cross-AZ data transfer between chatty services. Flag if detected architecturally.
6. Defer cost depth to `review-costs` — link rather than duplicate.

### 7. Assign Per-Pillar Scores

For each pillar, compute:

- **GREEN** — zero RED findings and at most one YELLOW.
- **YELLOW** — multiple YELLOWs or a single non-critical RED.
- **RED** — one or more critical REDs (public data, no backups, no authentication, etc.).

List the top three findings per pillar as "quick wins" — prefer the highest-impact RED or YELLOW items.

## Output Format

```
## Well-Architected Review — <workload>

**Account:** <id>     **Region:** <region>     **Mode:** <IaC | Live>

### Pillar Scores

| Pillar                  | Score  | Top finding |
| ----------------------- | ------ | ----------- |
| Operational Excellence  | YELLOW | No runbook in docs/runbooks/ |
| Security                | RED    | 2 public S3 buckets without block-public-access |
| Reliability             | GREEN  | Multi-AZ RDS, ASG across 3 AZs |
| Performance Efficiency  | YELLOW | No caching layer on read-heavy API |
| Cost Optimization       | YELLOW | 3 orphaned EBS volumes (~<size>) |

### Findings by Pillar

#### Operational Excellence
- [YELLOW] terraform/workload/main.tf — Owner tag missing on 4 of 12 resources.
...

#### Security
- [RED] s3://<bucket> — PublicAccessBlockConfiguration absent.
...

### Quick Wins (top 3 per pillar)
...

### Cross-References
- See `review-aws-iam` for IAM depth
- See `review-costs` for cost-hotspot depth
- See `review-disaster-recovery` for RTO/RPO audit

### Verdict: <GREEN | YELLOW | RED>
```

## Verdict

Report a workload-level verdict using the worst pillar score:

- **GREEN** — every pillar is GREEN.
- **YELLOW** — at least one pillar YELLOW and no RED.
- **RED** — any pillar is RED.

## Rules

1. **Read-only AWS calls only.** Use `get-*`, `describe-*`, `list-*` exclusively. Never emit `aws ec2 modify-*`, `aws s3api put-*`, `aws rds modify-*`, or any mutating command. Never propose running Terraform `apply` or `plan -out` that writes to backend state beyond what `review-drift` already permits.
2. **Never fabricate account IDs, ARNs, bucket names, or resource evidence.** If something cannot be verified from IaC or live read calls, mark it **INCONCLUSIVE**.
3. **Graceful skip.** If `aws` is not installed or credentials fail, fall back to IaC-only and mark live-dependent checks **SKIPPED**.
4. **Cross-reference, do not duplicate.** Link to the specialized skills (`review-aws-iam`, `review-costs`, `review-disaster-recovery`) for the depth they own.
5. **No persona.** Procedural and imperative only.

$ARGUMENTS
