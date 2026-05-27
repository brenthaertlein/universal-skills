---
name: review-disaster-recovery
description: "[pr-review-focus-area: Disaster Recovery] Audit DR readiness — backup coverage, declared RTO/RPO vs configured reality, failover paths, and whether DR has been exercised recently."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
argument-hint: "[service or directory]"
---

# Disaster-Recovery Readiness Review

Audit the disaster-recovery posture of a service or directory tree: which stateful assets exist, which have backups, whether retention satisfies declared RPO, whether a failover path is declared, and whether a restore has been exercised recently. This skill is strictly **read-only** — it inspects infrastructure-as-code and configuration artifacts only and never triggers a backup, restore, failover, or any other mutating operation.

## Invocation

The user runs `/review-disaster-recovery [service or directory]`. The argument is the path to scope the audit. If omitted, scan the repository root and report DR posture across all detected stateful assets.

## Execution Steps

Execute the steps in order. Record every asset and finding with a file path and line reference so reviewers can audit the judgement.

### 1. Enumerate Stateful Assets

Run the shared scope helper to learn what IaC artifacts exist. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/detect-iac-scope.sh` and fall back to `plugins/infra/scripts/detect-iac-scope.sh` when running from the plugin dev repo.

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/detect-iac-scope.sh"
[ -x "$SCRIPT" ] || SCRIPT="plugins/infra/scripts/detect-iac-scope.sh"
"$SCRIPT" "${1:-.}"
```

Use the JSON `terraform.modules`, `cloudformation.templates`, `helm.charts`, and `kubernetes.manifests` arrays to scope the scan. If backup status requires live cloud calls (for example to confirm last-snapshot timestamps or AWS Backup vault reachability), also run the auth helper:

```bash
AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
[ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
"$AUTH" all
```

If a provider's `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark its live checks SKIPPED with the `detail` field as the reason and continue with repo inspection only.

Then scan the in-scope files for resources that hold durable state:

- **Relational databases** — `aws_db_instance`, `aws_rds_cluster`, `google_sql_database_instance`, `azurerm_postgresql_server`, self-hosted Postgres/MySQL in Helm/Ansible.
- **NoSQL / warehouses** — `aws_dynamodb_table`, `google_bigquery_dataset`, `aws_redshift_cluster`, self-hosted Cassandra / MongoDB / Elasticsearch.
- **Object storage** — `aws_s3_bucket`, `google_storage_bucket`, `azurerm_storage_account`, MinIO deployments.
- **Persistent volumes** — Kubernetes `PersistentVolumeClaim`, `StatefulSet` volume templates, Nomad host volumes.
- **Message/queue durability** — long-lived Kafka topics, RabbitMQ durable queues, SQS FIFO queues with retention > 1 day.
- **Secret stores** — Vault storage backends, sealed secrets, SSM Parameter Store (SecureString).

Treat anything matching these patterns as in-scope. Attach an owner tag/label if declared.

### 2. Map to Backups

For each asset, locate its backup configuration in the repo:

- AWS Backup plans (`aws_backup_plan`, `aws_backup_selection`).
- RDS/Aurora `backup_retention_period`, `point_in_time_recovery`.
- DynamoDB `point_in_time_recovery` block and `aws_backup` coverage.
- S3 versioning, replication rules, lifecycle rules, Object Lock.
- GCS `versioning`, `lifecycle_rule`, cross-region replication.
- GCP SQL `backup_configuration`, `point_in_time_recovery_enabled`.
- Velero `Schedule` resources for Kubernetes workloads.
- Restic/Borg/duplicity schedules declared in Ansible.

If an asset has no backup declaration anywhere in the repo, record a finding — `NO BACKUP CONFIGURED`.

### 3. Compare Stated RTO/RPO to Config

Use AskUserQuestion to capture the committed recovery targets when they are not already documented in the repo:

- Committed RTO (time to restore service).
- Committed RPO (acceptable data loss window).
- Any regulatory/contractual floor on retention.

Then compare against the configuration discovered in Step 2:

- **Retention >= RPO?** A 1-hour RPO cannot be met by a nightly snapshot.
- **Cross-region / cross-account copy?** Single-region backups fail a regional outage.
- **Immutability?** Object Lock, Vault Lock, or equivalent against ransomware / accidental deletion.
- **Restore rehearsed?** Look for a restore log, runbook entry, or dated note in `docs/dr/` within the last 90 days.

Each mismatch is a finding ranked by severity (CRITICAL if RPO is unmet, HIGH for cross-region gap, MEDIUM for missing immutability, MEDIUM for stale rehearsal).

After comparing RTO/RPO to config, dispatch to the `principal-sre` subagent to stress-test the "restore tested recently" claim. The subagent applies its production-readiness lens — wishful-thinking detection, evidence sufficiency, hidden coupling between primary and "DR" copy. Integrate its findings into the report below; do not let it replace this skill's verdict labels.

```
Agent({
  subagent_type: "principal-sre",
  description: "Stress-test DR restore claims",
  prompt: "Review this DR posture: <RTO/RPO targets, per-asset backup config, cross-region status, last-tested evidence found in repo>. Stress-test the restore-tested-recently claim — what would actually happen at 3am if the primary region died? Return top findings in severity order."
})
```

### 4. Failover Path

For each asset and its consuming service:

- Is a standby / read-replica / warm-secondary declared in another region or zone?
- Is the cutover mechanism documented — Route 53 failover records, GCP Traffic Director routing, manual DNS change, application-level connection string swap?
- Is the RTO achievable given the cutover mechanism?
- Is there a data-consistency expectation post-failover (async replication lag, read-after-write guarantees)?

If the answer to "where does traffic go if the primary region is down?" cannot be found in the repo or runbook set, record a finding.

### 5. Report

Aggregate the findings into a per-asset matrix and a prioritized remediation list. Group findings by owning team when a team tag is available. Do not invent dates, restore evidence, or RPO commitments — missing inputs are marked `[needs input]` or `[INCONCLUSIVE]`.

## Output Format

```
## DR Readiness Review — <scope>

**Committed targets:** RTO=<value>, RPO=<value>  (source: user input / docs path)
**Assets in scope:** N stateful assets across M services

### Coverage matrix
| Asset | Type | Backup | Retention | RPO met | Cross-region | Immutable | Last tested | Owner |
|-------|------|--------|-----------|---------|--------------|-----------|-------------|-------|
| aws_db_instance.orders | RDS | aws_backup_plan.daily | 14d | yes | no | no | [needs input] | team-orders |
| aws_s3_bucket.artifacts | S3 | versioning + lifecycle | 90d | yes | no | Object Lock | n/a | team-platform |
| k8s pvc postgres-data | PVC | [NO BACKUP CONFIGURED] | - | no | - | - | - | team-orders |
...

### Failover paths
- orders DB — no standby declared; RTO 1h not achievable from snapshot alone.
- artifacts bucket — cross-region replication not enabled.
...

### Findings
- [CRITICAL] k8s pvc postgres-data — no backup configured (apps/orders/values.yaml:42)
- [HIGH] aws_db_instance.orders — single-region backup vault (terraform/rds.tf:18)
- [MEDIUM] aws_s3_bucket.artifacts — no cross-region replication
- [MEDIUM] orders — no restore rehearsal evidence in last 90 days

### Remediation priorities
1. Add a backup plan for postgres-data PVC (Velero Schedule).
2. Enable cross-region copy on aws_backup_plan.daily.
3. Schedule a quarterly restore rehearsal.

**Verdict:** <READY | GAPS | UNREADY>
```

## Verdict

- **READY** — every stateful asset has a backup configured, retention meets or exceeds committed RPO, cross-region/cross-account copy exists for tier-1 assets, a failover path is declared, and a restore has been exercised within the last 90 days.
- **GAPS** — backups exist for every asset but at least one of the following is missing: cross-region copy, immutability protection, documented failover path, or recent restore rehearsal. RPO is still met by configuration.
- **UNREADY** — any tier-1 stateful asset has no backup, configured retention fails to meet the committed RPO, or there is no declared failover path at all for a service that claims regional resilience.

## Rules

1. **Read-only** — never run `aws backup start-backup-job`, `gcloud sql backups create`, `velero backup create`, `terraform apply`, or any other mutating command. Never trigger a test restore.
2. **No fabricated dates** — "last tested" is only populated from a dated artifact in the repo (restore log, runbook entry, PR description). Missing dates are marked `[needs input]`.
3. **No fabricated RTO/RPO** — if the user does not supply committed targets and the repo does not declare them, mark the comparison `[INCONCLUSIVE]` and still report the raw configuration.
4. **Graceful SKIPPED** — if a CLI (`aws`, `gcloud`, `velero`, `kubectl`) is unavailable, rely on repo inspection only and mark any live checks SKIPPED.
5. **Never reveal backup credentials** — refer to vault/bucket identifiers by resource name, never echo access keys, tokens, or signed URLs.
6. **Defer depth to siblings** — cost concerns link out to `review-costs`; IAM permissions on backup vaults link out to `review-aws-iam` or `review-gcp-iam`.

$ARGUMENTS
