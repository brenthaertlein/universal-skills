---
name: assess-change-risk
description: "Blast-radius assessment for a pending Terraform plan, Ansible playbook, or Kubernetes manifest diff. Answers 'what could this take down?'"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Agent
argument-hint: "[path to plan file or diff]"
---

# Change-Risk Assessment

Evaluate the blast radius of a pending infrastructure change — Terraform plan, Ansible check-mode diff, or Kubernetes manifest diff — and report which resources could experience downtime, which downstream consumers reference them, and which changes touch network or IAM boundaries. This skill is strictly **read-only**; it parses already-generated plan artifacts and repository source and never invokes `apply`, `upgrade`, or any mutating command.

## Invocation

The user runs `/assess-change-risk [path to plan file or diff]`. The argument points to one of:

- A Terraform plan binary (requires a paired `terraform show -json <plan>` JSON export) or the JSON directly.
- An Ansible `--check --diff` output file.
- A `kubectl diff` output file.
- A raw `git diff` as a fallback when no planner output is available.

If the argument is omitted, scan the working tree for recent plan artifacts and ask the user to confirm which to assess.

## Execution Steps

Walk the steps in order. Record each change with a file path and line reference so reviewers can audit the source of the judgement.

### 1. Ingest Diff

First, run the shared scope helper to learn which IaC tool owns the diff. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/detect-iac-scope.sh` and fall back to `plugins/infra/scripts/detect-iac-scope.sh` when running from the plugin dev repo.

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/detect-iac-scope.sh"
[ -x "$SCRIPT" ] || SCRIPT="plugins/infra/scripts/detect-iac-scope.sh"
"$SCRIPT"
```

Use the JSON to record which IaC tools and modules are present in the repo so later steps can resolve dependent references against the right declaration set.

Then detect the artifact format by inspection:

- **Terraform JSON** — top-level `resource_changes[]` array. Parse directly.
- **Terraform binary plan** — invoke `terraform show -json <plan>` in the plan's directory. If `terraform` is unavailable, report SKIPPED and ask for the JSON form.
- **Ansible check diff** — parse `TASK [...]` + `changed` + `diff` blocks.
- **kubectl diff** — parse the unified-diff-per-object output with `# Source:` markers.
- **Generic git diff** — last-resort fallback. Heuristic classification only; note the reduced confidence in the report.

Never run `terraform plan`, `ansible-playbook` (without `--check`), or `kubectl apply`. Only read existing artifacts.

### 2. Classify Each Change

For every resource or task in the diff, assign an action category:

- **CREATE** — new resource. Low risk on its own.
- **UPDATE-IN-PLACE** — mutation without recreation. Medium risk.
- **REPLACE** — destroy + recreate. High risk; connection draining, DNS, and downstream ref rot are likely.
- **DELETE** — removal. Highest risk; anything referencing it breaks.

For Ansible tasks, map to the closest category (e.g. `file: state=absent` → DELETE; `service: state=restarted` → UPDATE-IN-PLACE with downtime flag).

Record the reason Terraform chose REPLACE (forces_new_resource attribute) so reviewers can evaluate whether the trigger is intentional.

### 3. Identify Dependents

For every REPLACE or DELETE resource, search the repository for references:

- Terraform interpolations (`aws_db_instance.primary.endpoint`, `${module.x.output}`).
- Hardcoded ARNs, project IDs, DNS names, or internal URLs.
- SSM parameter names, Secrets Manager secret names, GCP Secret Manager refs.
- Kubernetes `Service` names referenced by manifests, Helm values, or ingress backends.
- Configuration files, deploy manifests, and alert definitions that name the resource.

List each dependent with its file and line, plus the reference style (direct, SSM, DNS, etc.).

### 4. Network and IAM Specials

Regardless of change category, flag any change that touches:

- Security groups, NACLs, firewall rules, `NetworkPolicy`, `CiliumNetworkPolicy`.
- IAM policies, role trust policies, GCP IAM bindings, Kubernetes `Role` / `ClusterRole` / `RoleBinding`.
- Route tables, transit-gateway attachments, VPC peering, VPN/DX.
- DNS zones and records, service meshes, ingress controllers.
- TLS certificates, ACM imports, cert-manager `Certificate` resources.
- KMS key policies, GCP KMS IAM, Vault policies.

Each item gets its own section in the report regardless of whether the classification would otherwise mark it low risk.

### 5. Rehearsal Check

Determine whether the change has been tried in a non-production environment first:

- Look for an `environment`, `env`, or `stage` label on the resources in the plan.
- Correlate with the Terraform workspace name, directory name (`envs/prod`, `envs/staging`), or Helm release namespace.
- Scan recent git history in sibling environment directories for commits touching the same resource types.

If the plan targets production and no evidence of prior rehearsal in a lower environment exists, emit a dedicated warning.

### 6. Senior Review

Dispatch to the `principal-sre` subagent with the evidence collected in steps 1-5. Ask it to apply its production-readiness lens (failure modes, recovery path, blast radius) and rank the findings in severity order. Receive back a prioritized list and integrate it into the Output Format below — do not replace this skill's verdict contract.

```
Agent({
  subagent_type: "principal-sre",
  description: "Rank change-risk findings",
  prompt: "Review this change diff: <summary of artifact, classified changes, dependents, network/IAM specials, rehearsal evidence>. Rank the blast-radius findings in severity order and call out any that should block ship. Return top findings in severity order."
})
```

## Output Format

```
## Change-Risk Assessment

**Source artifact:** <path>
**Detected format:** <terraform-json | terraform-plan | ansible-check | kubectl-diff | git-diff>
**Target environment:** <env or unknown>

**Change summary:** +N create, ~N update, !N replace, -N delete

### High-blast-radius changes
- aws_db_instance.primary — REPLACE (forces_new: engine_version).
  Dependents: 4 apps reference its endpoint via SSM param /rds/primary/endpoint.
  Downtime window: until SSM refresh + app restart.
- kubernetes_deployment.api — UPDATE-IN-PLACE with rolling strategy; surge=1.
...

### Network & IAM changes
- aws_security_group_rule.web-ingress — new 0.0.0.0/0 on port 22. Review.
- aws_iam_role_policy.lambda-exec — Action "*" added on Resource "*". Review.
...

### Dependents table
| Resource | Action | Dependent | Reference style | File |
|----------|--------|-----------|-----------------|------|
| aws_db_instance.primary | REPLACE | apps/orders | SSM param | apps/orders/config.yaml:17 |
...

### Rehearsal
- Target env: prod
- Prior rehearsal: none detected in envs/staging
- Recommendation: stage first

**Verdict:** <LOW | MEDIUM | HIGH | CRITICAL>
```

## Verdict

- **LOW** — only CREATE or cosmetic UPDATE-IN-PLACE changes, no network or IAM surface touched, no REPLACE or DELETE resources.
- **MEDIUM** — UPDATE-IN-PLACE on stateful resources, or network/IAM changes that are additive and narrowly scoped, with no dependents affected.
- **HIGH** — at least one REPLACE on a resource with declared dependents, or security group / IAM widening, or the change targets production without rehearsal evidence.
- **CRITICAL** — any DELETE on a stateful resource (database, persistent volume, object store), IAM change granting `*` on `*`, public-ingress opening, or simultaneous REPLACE of more than one dependency-shared resource.

## Rules

1. **Read-only** — never run `terraform apply`, `ansible-playbook` without `--check`, `kubectl apply`, or `helm upgrade`. Never invoke `terraform plan` either — the plan artifact is an input.
2. **No fabricated dependents** — only list references found by grep in the repository. If a dependent is suspected but not grep-visible, mark `[INCONCLUSIVE]`.
3. **Graceful SKIPPED** — if `terraform` is not installed and the input is a binary plan, skip parsing and request JSON form; do not attempt recovery.
4. **Never invent environment labels** — if the plan does not declare an environment, report `unknown` rather than guessing from filenames alone.
5. **Network and IAM always surface** — even a one-line SG or policy diff gets its own section in the report.
6. **Do not propose remediations that mutate** — recommendations are limited to "stage first," "split into smaller diffs," "notify consumers," or "schedule maintenance window."

$ARGUMENTS
