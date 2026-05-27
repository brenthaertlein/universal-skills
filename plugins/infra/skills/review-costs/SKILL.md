---
name: review-costs
description: "[pr-review-focus-area: Cloud Costs] Flag cost hotspots in Terraform plans and live cloud inventory - oversized instances, orphaned volumes, idle load balancers, untagged resources, NAT egress."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - WebFetch
  - AskUserQuestion
argument-hint: "[aws|gcp|auto]"
---

# Cloud Cost Review

Surface cost hotspots across Terraform plans and live cloud inventory, rank them by certainty of waste, and estimate monthly spend where pricing data is available. This skill is **read-only** — it never modifies resources, attaches/detaches anything, or runs mutating CLI commands.

## Invocation

The user runs `/review-costs [aws|gcp|auto]`.

- `aws` — scope to AWS only (Terraform providers + live account via `aws` CLI).
- `gcp` — scope to GCP only (Terraform providers + live account via `gcloud`).
- `auto` (default when omitted) — detect cloud from Terraform providers, `.tf` backends, or available CLI credentials, and run whichever surfaces.

## Execution Steps

### 1. Determine Scope

Run the shared scope helper to learn what IaC artifacts exist. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/detect-iac-scope.sh` and fall back to `plugins/infra/scripts/detect-iac-scope.sh` when running from the plugin dev repo.

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/detect-iac-scope.sh"
[ -x "$SCRIPT" ] || SCRIPT="plugins/infra/scripts/detect-iac-scope.sh"
"$SCRIPT"
```

Use the JSON `.terraform.modules[]` to pick module roots for the IaC pass. Then use AskUserQuestion to narrow the review:

```
Question: "Which scope should I audit?"
Options:
  1. "Terraform plan only" - "Parse IaC for likely cost issues, no cloud calls"
  2. "Live account only" - "Inventory the live cloud, skip IaC parsing"
  3. "Both" - "Cross-reference IaC against live inventory"
```

When the user picks `Live account only` or `Both`, probe credentials with the auth helper for the chosen cloud:

```bash
AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
[ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
"$AUTH" aws    # or: gcp
```

If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark the live scan SKIPPED with the `detail` field as the reason, fall back to `Terraform plan only`, and note the degradation in the report header.

### 2. IaC Scan

When Terraform plan scope is enabled:

1. Locate module roots (directories containing `*.tf` + `.terraform/`). Do NOT run `terraform init`.
2. Generate the plan JSON with `terraform plan -out=/tmp/tfplan -lock=false` followed by `terraform show -json /tmp/tfplan`. Skip the module with SKIPPED if it is not initialized.
3. Walk `planned_values.root_module` and flag:
   - `aws_instance` / `google_compute_instance` with instance families above `*.large` without matching autoscaling rules.
   - `aws_ebs_volume` / `google_compute_disk` with `size` > 500 GiB or `type` of `io2` / `pd-ssd` without a declared throughput need.
   - `aws_lb` / `google_compute_forwarding_rule` that expose no target group attachments in the plan.
   - `aws_nat_gateway` count per VPC (each one is a recurring fixed charge plus egress).
   - `aws_eip` / `google_compute_address` without an attachment in the plan.
   - `aws_db_instance` / `google_sql_database_instance` with `multi_az` or `availability_type=REGIONAL` on non-production environments.
   - Any resource lacking the org-standard tags (surface the resource type and the missing keys).

### 3. Live Scan

When live account scope is enabled, run read-only inventory calls:

- **AWS**:
  - `aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags]'`
  - `aws ec2 describe-volumes --filters Name=status,Values=available` (orphaned volumes)
  - `aws ec2 describe-addresses --query 'Addresses[?AssociationId==null]'` (unassociated EIPs)
  - `aws elbv2 describe-load-balancers` and `describe-target-groups --target-group-arn` to find LBs with zero healthy targets
  - `aws ec2 describe-nat-gateways`
  - `aws rds describe-db-instances`
- **GCP**:
  - `gcloud compute instances list --format=json`
  - `gcloud compute disks list --filter='-users:*'` (orphaned disks)
  - `gcloud compute addresses list --filter='status=RESERVED'`
  - `gcloud compute forwarding-rules list`
  - `gcloud sql instances list`

If the CLI is missing or unauthenticated, mark the live scan SKIPPED for that cloud and continue.

### 4. Rank Findings

Assign every finding exactly one category:

- **orphaned** — unattached volume, unassociated EIP, LB with no targets, idle NAT gateway. High confidence of waste.
- **oversized** — instance family larger than workload evidence supports. Medium confidence; flag as "needs metrics to confirm."
- **architectural** — NAT egress concentration, cross-region data transfer, multi-AZ on dev, over-provisioned RDS/CloudSQL. Low-to-medium confidence; requires human review.
- **tagging** — resource missing org-standard tags. No direct $ impact but blocks chargeback.

### 5. Estimate Monthly Cost

For each finding, include a `Est $/mo` column with a confidence label of **Low**, **Med**, or **High**:

- **High** — the resource's instance type / volume type appears in a pricing snapshot retrieved via WebFetch from the official AWS or GCP pricing page during this session, and usage is fixed-rate (e.g. NAT hourly, EIP idle fee).
- **Med** — a generic band for the resource class (e.g. "orphaned gp3 500GiB ~ $40/mo") based on published on-demand list prices.
- **Low** — structural estimate only (e.g. "NAT egress cost scales with traffic - needs VPC flow logs to bound").

If pricing cannot be retrieved, record `Est $/mo` as `needs pricing` and set confidence to Low.

## Output Format

```
## Cost Review - <scope>

**Scope:** <Terraform plan only | Live account only | Both>
**Cloud:** <aws | gcp>

| Resource | Category | Est $/mo | Confidence | Recommendation |
|----------|----------|----------|------------|----------------|
| vol-0abc123 | orphaned | $40 | High | Detach confirmed, delete after 7-day hold |
| i-0def456 (m5.4xlarge) | oversized | $560 | Med | Rightsize pending CPU/mem history |
| nat-0ghi789 (us-east-1b) | architectural | $35 fixed + egress | Low | Consolidate with AZ-a NAT or VPC endpoints |
| aws_s3_bucket.logs | tagging | n/a | n/a | Missing `owner`, `cost-center` tags |

**Totals:** orphaned: N ($X), oversized: N ($X), architectural: N (varies), tagging: N
**Verdict:** <CLEAN | REVIEW | HIGH-WASTE>
```

## Verdict

- **CLEAN** — no orphaned findings, no oversized findings, tagging gaps below 5% of resources.
- **REVIEW** — at least one oversized or architectural finding, or tagging gaps above 5%, but no orphaned waste. Human judgment required.
- **HIGH-WASTE** — one or more orphaned findings, or aggregate `High`-confidence monthly estimate exceeds a threshold the user can eyeball in the totals.

## Rules

1. **Read-only.** Never run `aws ec2 terminate-instances`, `aws ec2 delete-volume`, `gcloud compute instances delete`, `terraform apply`, or any mutating call.
2. **Graceful skip.** Missing `aws` / `gcloud` CLI, expired credentials, or uninitialized Terraform modules produce SKIPPED entries, not failures.
3. **No fabricated prices.** Never invent dollar figures. Use only pricing retrieved during the session or explicit generic bands, and always tag with Low/Med/High confidence.
4. **No fabricated resource IDs.** If a resource ID is not in the plan JSON or live API response, do not include it.
5. **Rightsizing needs evidence.** Never claim an instance is oversized without a metric source; mark it "needs metrics to confirm."
6. **Respect scope.** `aws` and `gcp` arguments must not cause cross-cloud calls.

$ARGUMENTS
