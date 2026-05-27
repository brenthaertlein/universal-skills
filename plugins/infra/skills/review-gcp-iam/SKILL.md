---
name: review-gcp-iam
description: "[pr-review-focus-area: GCP IAM] GCP IAM least-privilege audit across project, folder, and org policies, including service-account usage and impersonation paths."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - WebFetch
argument-hint: "[project-id or Terraform path]"
---

# GCP IAM Least-Privilege Audit

Audit IAM bindings across a GCP project, folder, or organization, plus any `google_*_iam_*` declarations in Terraform, and flag excess privilege, risky service-account shapes, and external principals. This skill is **read-only** — it never calls `add-iam-policy-binding`, `set-iam-policy`, or any mutating API.

## Invocation

The user runs `/review-gcp-iam <project-id-or-path>`.

- If the argument looks like a project ID (matches `[a-z][-a-z0-9]{4,28}[a-z0-9]`), collect live bindings with `gcloud`.
- If the argument is a filesystem path, parse Terraform under that path.
- If no argument is provided, scan the current working directory for Terraform files first, then ask the user for a project ID before hitting any GCP API.

## Execution Steps

Run the steps in order. Each step reports **PASS**, **FINDING**, **SKIPPED** (tool or credential missing), or **INCONCLUSIVE**.

### 1. Collect Bindings

Before any live call, probe GCP credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

```bash
AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
[ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
"$AUTH" gcp
```

If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark live collection **SKIPPED** with the `detail` field as the reason and continue with whatever Terraform sources are available. Never invent project IDs, role names, or member identities.

Then gather the binding set from the best available source. Do not mix fabricated data with collected data.

- **Live project**: `gcloud projects get-iam-policy <project-id> --format=json`
- **Folder** (if user consents): `gcloud resource-manager folders get-iam-policy <folder-id> --format=json`
- **Org** (if user consents): `gcloud organizations get-iam-policy <org-id> --format=json`
- **Terraform**: `grep -rnE 'google_(project|folder|organization|service_account)_iam_(binding|member|policy)' <path>` then Read each matched file.

### 2. Flag Primitive and Basic Roles

Enumerate members bound to any of these roles and emit one FINDING per member:

- `roles/owner`
- `roles/editor`
- `roles/viewer` (lower severity, still flag on human users)

Classify severity HIGH for `owner`/`editor` on service accounts or group principals; MEDIUM for human users; LOW for `viewer`. Do not classify `roles/viewer` on automation SAs as a finding — note it as INFO only.

### 3. Service-Account Hygiene

For every service account referenced in the binding set, check:

1. **User-managed keys** — `gcloud iam service-accounts keys list --iam-account=<email> --managed-by=user`. Any key older than 90 days → FINDING (HIGH).
2. **Default compute SA with editor** — if `<project-number>-compute@developer.gserviceaccount.com` holds `roles/editor`, flag HIGH.
3. **Impersonation chains** — enumerate principals with `roles/iam.serviceAccountTokenCreator` or `roles/iam.serviceAccountUser` on other SAs. Walk the graph two hops deep and report any path that terminates at a SA bound to `roles/owner` or `roles/editor`.
4. **Cross-project impersonation** — impersonators whose principal domain differs from the target SA's project → FINDING (MEDIUM).

### 4. External Principals and Allowed Domains

Inspect every member string and flag:

- `allUsers` on any role → FINDING (CRITICAL).
- `allAuthenticatedUsers` on any role → FINDING (HIGH).
- `user:` or `group:` members whose email domain is outside the org's allowed set. Determine the allowed set from `gcloud organizations list` plus any `domain:` restrictions in the org policy, or ask the user. If the allowed set cannot be determined, mark **INCONCLUSIVE** per external finding.

If the permission reference for a role is unclear, use WebFetch against `https://cloud.google.com/iam/docs/understanding-roles` to confirm the role's included permissions before classifying severity. Never fabricate the permission list.

### 5. Unused and Stale Grants

Use IAM Recommender output to mark stale grants.

- `gcloud recommender recommendations list --project=<project-id> --recommender=google.iam.policy.Recommender --format=json`
- Join each recommendation's `content.overview.member` and `role` against the binding set from Step 1.
- Every match becomes a FINDING (MEDIUM) tagged `STALE`.

If Recommender API is disabled or returns empty, report SKIPPED with a note to enable `recommender.googleapis.com`, and suggest the user run `/triage-gcp-recommender` for a fuller pass.

## Output Format

```
## GCP IAM Audit — <project-id or path>

### Summary
| Check                     | Status   | Count |
| ------------------------- | -------- | ----- |
| Binding collection        | PASS     | 47 bindings |
| Primitive/basic roles     | FINDING  | 3 |
| Service-account hygiene   | FINDING  | 2 |
| External principals       | PASS     | 0 |
| Stale grants              | SKIPPED  | Recommender disabled |

### Findings
| Severity | Category      | Principal                              | Role              | Source                  |
| -------- | ------------- | -------------------------------------- | ----------------- | ----------------------- |
| HIGH     | primitive     | user:alice@example.com                 | roles/owner       | project IAM policy      |
| HIGH     | sa-key-age    | sa:ci@<project>.iam.gserviceaccount... | n/a (142d old)    | iam.serviceAccounts.keys|
| MEDIUM   | stale-grant   | group:legacy@example.com               | roles/editor      | Recommender             |

**Verdict: NEEDS-REMEDIATION** (2 HIGH, 1 MEDIUM)
```

## Verdict

- **CLEAN** — zero findings across all steps.
- **NEEDS-REMEDIATION** — one or more MEDIUM or HIGH findings.
- **CRITICAL** — any CRITICAL finding (for example, `allUsers` bound to any non-public role).
- **INCONCLUSIVE** — collection failed or the allowed-domain set could not be determined for a majority of external principals.

## Rules

1. **Read-only.** Never run `gcloud projects add-iam-policy-binding`, `remove-iam-policy-binding`, `set-iam-policy`, `iam service-accounts keys create`, or any `gcloud * create|update|delete` variant. Only `get-iam-policy`, `describe`, and `list` are permitted.
2. **Graceful skip.** If `gcloud` is missing, unauthenticated, or lacks permission for a call, mark that step SKIPPED with the reason and continue.
3. **Never fabricate.** Do not invent project IDs, principal emails, role names, SA emails, or permission lists. When the data is unavailable, emit INCONCLUSIVE and move on.
4. **Cross-skill handoff.** For deep stale-grant analysis, defer to `/triage-gcp-recommender`. For in-cluster permissions on GKE, defer to `/review-kubernetes-rbac`.
5. **Scope respect.** Do not query folders or organizations without explicit user confirmation; project scope is the default.

$ARGUMENTS
