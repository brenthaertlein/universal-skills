---
name: triage-gcp-recommender
description: "Pull GCP Recommender API findings (IAM, rightsizing, idle VMs, commitment use, unattended project) and rank by dollar / risk impact."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[project-id]"
---

# GCP Recommender Triage

Pull recommendations from the GCP Recommender API for a project, normalize them into a single shape, and rank by dollar impact and risk. This skill is **read-only** — it only issues `gcloud recommender recommendations list` and `describe` calls, and never marks, applies, or dismisses any recommendation.

## Invocation

The user runs `/triage-gcp-recommender <project-id>`.

If no project ID is supplied, read `gcloud config get-value project` and confirm with the user before proceeding. Do not fabricate a project ID.

## Execution Steps

Execute in order. For each step report **PASS**, **FINDING** (count), **SKIPPED**, or **INCONCLUSIVE**.

### 1. Verify Access

1. Probe GCP credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

   ```bash
   AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
   [ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
   "$AUTH" gcp
   ```

   If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, report SKIPPED entirely with the `detail` field as the reason and stop.
2. Confirm Recommender API is enabled for the project: `gcloud services list --enabled --project=<project-id> --filter=config.name=recommender.googleapis.com`. If disabled, report SKIPPED with a remediation note and stop.
3. Record the project number with `gcloud projects describe <project-id> --format="value(projectNumber)"` for use in resource cross-references.

### 2. List Recommenders

Query each recommender below. Use `gcloud recommender recommendations list --project=<project-id> --location=global --recommender=<id> --format=json` for global recommenders, and enumerate regions/zones for regional ones (via `gcloud compute regions list` and `gcloud compute zones list`).

| Recommender ID                                   | Scope     | Category    |
| ------------------------------------------------ | --------- | ----------- |
| `google.iam.policy.Recommender`                  | project   | security    |
| `google.compute.instance.MachineTypeRecommender` | zonal     | cost        |
| `google.compute.instance.IdleResourceRecommender`| zonal     | cost        |
| `google.compute.commitment.UsageCommitmentRecommender` | regional | cost  |
| `google.cloudsql.instance.IdleRecommender`       | regional  | cost        |
| `google.cloudsql.instance.OverprovisionedRecommender` | regional | cost    |
| `google.resourcemanager.projectUtilization.Recommender` | project | hygiene |
| `google.compute.disk.IdleResourceRecommender`    | zonal     | cost        |

If a single recommender call fails (API disabled, permission denied, quota), record it as SKIPPED and continue — never abort the run on one failure.

### 3. Normalize

For every recommendation returned, produce a record with these fields:

```
{
  recommender:   <recommender id>,
  recommendation_id: <name>,
  resource:      <targetResources[0] or content.operationGroups[].operations[].resource>,
  impact_type:   COST | SECURITY | RELIABILITY | PERFORMANCE | MANAGEABILITY,
  impact_value:  { currency: USD, monthly: <float> } | { risk: LOW|MEDIUM|HIGH },
  state:         ACTIVE | CLAIMED | SUCCEEDED | FAILED | DISMISSED,
  description:   content.overview.description or content.description
}
```

Use `primaryImpact.costProjection.cost.units` and `.nanos` for the monthly dollar amount; convert nanos to fractional dollars. When `costProjection` is absent, leave `impact_value.monthly` null and mark the record `impact_type=SECURITY` or `RELIABILITY` as indicated by the API payload.

### 4. Group and Rank

1. Group records by `recommender`.
2. Within each group, sort by `impact_value.monthly` descending; records without a dollar value sort after priced ones, ranked by `priority` (`P1 > P2 > P3 > P4`).
3. Compute a group subtotal (sum of monthly dollars for ACTIVE records only).
4. Compute a grand total across all cost groups.

### 5. Cross-Link to IAM

For every `google.iam.policy.Recommender` record:

1. Emit the target principal and role in a dedicated column.
2. If the user previously ran `/review-gcp-iam` in this session and the resulting findings are available, mark any overlap with an `also-flagged-by:review-gcp-iam` tag.
3. If no prior output exists, recommend the user run `/review-gcp-iam <project-id>` for correlated context, but do not invoke it automatically.

## Output Format

```
## GCP Recommender Triage — <project-id>

### Cost — Compute Rightsizing  (subtotal: $412.30/mo)
| Resource                              | Current      | Suggested | $/mo saved | Priority |
| ------------------------------------- | ------------ | --------- | ---------- | -------- |
| zones/us-central1-a/instances/web-07  | n2-standard-8| n2-standard-4 | $198.00 | P1 |
| zones/us-central1-a/instances/web-09  | n2-standard-8| n2-standard-4 | $198.00 | P1 |

### Cost — Idle Resources  (subtotal: $86.12/mo)
| Resource                                   | Idle since | $/mo | Priority |
| ------------------------------------------ | ---------- | ---- | -------- |
| zones/us-west1-b/disks/scratch-old         | 64 days    | $12.40 | P2 |

### Security — IAM Policy  (8 findings)
| Principal                   | Role           | Stale since | Cross-ref         |
| --------------------------- | -------------- | ----------- | ----------------- |
| user:bob@example.com        | roles/editor   | 91 days     | also-flagged-by:review-gcp-iam |

### Hygiene — Project Utilization  (1 finding)
| Project        | Signal              | Action           |
| -------------- | ------------------- | ---------------- |
| <project-id>   | unattended 120 days | review ownership |

**Grand total (cost): $498.42/mo across 14 active recommendations**
**Verdict: TRIAGE-READY**
```

## Verdict

- **CLEAN** — zero active recommendations across all recommenders.
- **TRIAGE-READY** — recommendations exist and have been ranked. This is the normal happy-path outcome.
- **INCONCLUSIVE** — Recommender API disabled or a majority of recommender calls returned permission-denied; output is not complete.

## Rules

1. **Read-only.** Only `gcloud recommender recommendations list|describe`, `gcloud services list`, `gcloud projects describe`, `gcloud auth list`, `gcloud compute regions list`, and `gcloud compute zones list` are permitted. Never call `mark-claimed`, `mark-succeeded`, `mark-failed`, `mark-dismissed`, or any `gcloud * create|update|delete` variant.
2. **Graceful skip.** Missing `gcloud`, missing credentials, disabled API, quota errors, or permission errors per-recommender all resolve to SKIPPED with a recorded reason.
3. **Never fabricate.** Do not invent dollar figures, resource IDs, priority values, or recommender names. If `costProjection` is missing, leave it null and say so.
4. **No auto-linking to other skills.** Mention `/review-gcp-iam` as a suggested next step but never invoke it as part of this run.
5. **Deterministic ranking.** Always sort by monthly impact first, then by priority, then by resource name — never by API return order.

$ARGUMENTS
