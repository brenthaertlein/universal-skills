---
name: review-drift
description: "Detect drift between IaC state (Terraform/Pulumi/CloudFormation) and live cloud or baremetal reality."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[module path]"
---

# IaC Drift Review

Compare declared infrastructure-as-code state against live cloud or baremetal reality, classify each drifted resource, and surface likely owners. This skill is **read-only** — it never runs `apply`, `destroy`, `upgrade`, or any mutating command.

## Invocation

The user runs `/review-drift [module path]`. When no argument is supplied, scan from the repo root and auto-detect IaC modules. When a path is supplied, scope detection and planning to that directory and its descendants.

## Execution Steps

Run the steps in order. For each step, report **PASS**, **FAIL**, **SKIPPED** (tool or credential missing), or **N/A** (no matching files).

### 1. Detect IaC Tool

Run the shared scope helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/detect-iac-scope.sh` and fall back to `plugins/infra/scripts/detect-iac-scope.sh` when running from the plugin dev repo.

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/detect-iac-scope.sh"
[ -x "$SCRIPT" ] || SCRIPT="plugins/infra/scripts/detect-iac-scope.sh"
"$SCRIPT" "${1:-.}"
```

Parse the JSON output. Process the modules each tool reports independently and aggregate results:

| Tool           | JSON field                              |
| -------------- | --------------------------------------- |
| Terraform      | `.terraform.present` + `.terraform.modules[]` |
| Pulumi         | `.pulumi.present` + `.pulumi.stacks[]`        |
| CloudFormation | `.cloudformation.present` + `.cloudformation.templates[]` |

If none of the three are `present: true`, report SKIPPED with the reason "no IaC artifacts detected" and exit with verdict INCONCLUSIVE.

### 2. Plan Without Apply

For each detected tool, run the non-mutating diff command:

- **Terraform**: `terraform plan -detailed-exitcode -no-color -lock=false` in each module directory that has `.terraform/` present. Exit code `0` = no changes, `2` = drift present, `1` = error. If the module is not initialized, mark SKIPPED for that module — do NOT run `terraform init`.
- **Pulumi**: `pulumi preview --diff --non-interactive` from the stack directory. A non-empty resource diff = drift present.
- **CloudFormation**: `aws cloudformation detect-stack-drift --stack-name <name>` followed by `describe-stack-resource-drifts`. Any status other than `IN_SYNC` = drift present.

If credentials are missing, a state lock is held, or the provider is unauthenticated, mark the module INCONCLUSIVE and continue. Do not attempt to acquire credentials or break locks.

### 3. Classify Drift

For every drifted resource returned by step 2, assign exactly one tag:

- **added-outside-IaC** — resource exists live but not in state (Terraform `# forgets`, CFN `NOT_CHECKED` with live match, Pulumi `read` diff).
- **modified-outside-IaC** — attributes changed live relative to state (Terraform `~`, Pulumi `update`, CFN `MODIFIED`).
- **deleted-outside-IaC** — resource in state but absent live (Terraform `-`, Pulumi `delete`, CFN `DELETED`).
- **provider-side** — cosmetic noise from the provider: attribute reordering, computed-after-apply fields, default-value fills, tag key reorder. These do not count toward the verdict.

When a classification is ambiguous (e.g. partial read), mark it `unclear` and include the raw plan fragment in the report appendix rather than guessing.

### 4. Identify Owner

For each non-noise drifted resource:

1. Read tags / labels from the plan output for `owner`, `team`, `managed_by`, `cost-center`, or `service`. Surface the first match.
2. Cross-reference `CODEOWNERS` (root, `.github/`, or `docs/`) for the IaC file that declared the resource. If a CODEOWNERS entry matches, list its owners alongside the tag owner.
3. If neither source yields an owner, mark the row `unknown` — do NOT infer an owner from author history or guesswork.

### 5. Report

Group findings by owner/team first, then by severity (deleted > modified > added > provider-side). Render the report shape below.

## Output Format

```
## Drift Report - <module>

| Resource | Type | Drift | Likely cause | Owner |
|----------|------|-------|--------------|-------|
| aws_security_group.web | modified | ingress rule added | click-ops | platform |
| aws_s3_bucket.logs | added-outside-IaC | bucket exists live, not in state | manual console | unknown |
| google_compute_disk.cache | deleted-outside-IaC | disk removed live, still in state | cleanup script | sre |

**Totals:** added: N, modified: N, deleted: N, provider-noise: N
**Verdict:** <CLEAN | DRIFT-PRESENT | INCONCLUSIVE>
```

Include a `### Appendix: unclear classifications` section only when step 3 produced `unclear` rows, and paste the verbatim plan fragment for each.

## Verdict

- **CLEAN** — Terraform plan exits `0`, Pulumi preview is empty, or CloudFormation returns `IN_SYNC`; alternatively, only `provider-side` entries remain after classification.
- **DRIFT-PRESENT** — one or more `added-outside-IaC`, `modified-outside-IaC`, or `deleted-outside-IaC` rows exist.
- **INCONCLUSIVE** — credentials missing, state lock held, provider unauthenticated, module not initialized, or no IaC tool detected. Never promote INCONCLUSIVE to CLEAN.

## Rules

1. **Read-only.** Never run `terraform apply`, `terraform init`, `terraform refresh`, `pulumi up`, `pulumi refresh`, `aws cloudformation update-stack`, or any mutating operation.
2. **Graceful skip.** If the required CLI (`terraform`, `pulumi`, `aws`) is not installed, or credentials are missing, mark the affected module SKIPPED and continue.
3. **No fabrication.** Never invent resource ARNs, IDs, owners, or drift causes. When the plan output is ambiguous, mark the row `unclear` and quote the raw plan fragment.
4. **No state mutation.** Do not break state locks, do not pass `-lock=false` when a lock is legitimately held, do not write to remote state backends.
5. **Scope discipline.** Respect the argument path — do not traverse above it. When no argument is supplied, stop at the repo root and do not follow symlinks out of the tree.

$ARGUMENTS
