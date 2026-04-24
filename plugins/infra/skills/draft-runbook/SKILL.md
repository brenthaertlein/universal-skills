---
name: draft-runbook
description: "Generate or refresh an operational runbook for a service, derived from its code, deploy config, existing alerts, and prior incidents."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
argument-hint: "<service-name>"
---

# Draft Service Runbook

Assemble an operational runbook for a service by inspecting its source code, deployment manifests, alert definitions, and prior incident artifacts. This skill is strictly **read-only** — it writes a draft to stdout or to a pre-agreed docs path, and never deploys, restarts, or otherwise mutates the service it documents.

## Invocation

The user runs `/draft-runbook <service-name>`. The argument names the service whose runbook should be produced. If the argument is omitted, ask the user which service to target before proceeding.

## Execution Steps

Work through the steps in order. For any step where a required artifact is missing, mark the corresponding runbook section `[needs input]` and continue — never fabricate a dependency, endpoint, or alert threshold.

### 1. Locate Service

Search the repository for the service footprint:

- Source tree: `services/<name>/`, `apps/<name>/`, or a top-level directory matching the argument.
- Container build: `Dockerfile`, `Containerfile`, or image tag references in CI.
- Deploy manifests: Helm chart at `charts/<name>/`, Kustomize overlay, raw Kubernetes YAML, Nomad job, or systemd unit.
- Alert definitions: Prometheus recording/alerting rules, CloudWatch alarms in Terraform, GCP `google_monitoring_alert_policy` resources, Grafana alert JSON.
- Prior incidents: any `docs/postmortems/` or `docs/incidents/` entries mentioning the service.

If the service cannot be located, stop and ask the user for the code path before continuing.

### 2. Infer Surface

From the located artifacts, extract:

- **Inbound dependencies** — HTTP routes, gRPC services, queue consumers, cron triggers.
- **Outbound dependencies** — databases, caches, message brokers, third-party APIs. Read connection strings, DSNs, and environment variable references only; never dereference live credentials.
- **Declared SLOs** — derived from alert thresholds (latency, error rate, saturation).
- **On-call rotation** — look for `OWNERS`, `CODEOWNERS`, PagerDuty/Opsgenie service identifiers, or a `team:` label in manifests.

Record each inference with a file path and line number so reviewers can audit the source.

### 3. Prompt for Gaps

Use AskUserQuestion to fill gaps the codebase cannot answer. Ask only the questions whose answers are missing from the repo. Example set:

- Escalation path beyond the primary on-call rotation.
- Known flaky behaviors or "yes, that's expected" quirks.
- Break-glass owner authorized to bypass change-management.
- Any customer communication template tied to this service.

Keep the question set to at most four items per invocation.

Then dispatch to the `principal-sre` subagent to identify what the operator at 3am will need that the code does not say. Ask it to apply its on-call lens to the inferred surface — hidden coupling, retry-storm risk, where the obvious first response is wrong. Integrate its findings into the `Common Failures` and `Known Quirks` sections of the runbook below; do not let it replace this skill's section structure or the "verify before running in prod" discipline.

```
Agent({
  subagent_type: "principal-sre",
  description: "Identify operator-at-3am gaps",
  prompt: "Review this service surface: <inbound/outbound deps, declared SLOs, alert rules, on-call rotation, prior incidents>. What does the operator at 3am need to know that the code and manifests don't say? Where will the obvious first response make it worse? Return top findings in severity order."
})
```

### 4. Assemble Runbook

Build the runbook using the section order below. Every "first response" step must end with the phrase "verify before running in prod."

1. **Purpose** — one paragraph. What the service does and who depends on it.
2. **Architecture sketch** — ASCII box diagram of inbound/outbound edges.
3. **Dependencies** — table of upstreams/downstreams with criticality.
4. **Dashboards & alerts** — list each alert rule with its metric, threshold, and linked runbook section.
5. **Common failures** — one subsection per alert rule, each with symptoms, likely causes, and first-response steps.
6. **Escalation** — primary, secondary, and break-glass contacts.
7. **Rollback procedure** — inferred from deploy tooling (Helm rollback, ArgoCD sync to prior revision, Terraform revert-and-plan).
8. **Known quirks** — gathered from Step 3 and prior postmortems.

### 5. Select Output Mode

Check whether `docs/runbooks/<service>.md` already exists.

- **Full write mode** — no existing runbook. Emit the complete markdown document.
- **Diff mode** — runbook exists. Produce a unified diff against the current file so reviewers can see only the proposed changes.

Never overwrite or delete files; the skill returns text for the user to apply.

## Output Format

```
## Runbook Draft — <service>

**Mode:** <FULL-WRITE | DIFF>
**Source path:** docs/runbooks/<service>.md
**Inferred from:** <N source files, N manifests, N alert rules>
**Gaps filled by user:** <N answers>

---

# <service> Runbook

## Purpose
...

## Architecture
...

## Dependencies
| Direction | Target | Criticality | Notes |
|-----------|--------|-------------|-------|
...

## Dashboards & Alerts
...

## Common Failures
### <AlertName>
- Symptoms: ...
- Likely causes: ...
- First response: ... — verify before running in prod.

## Escalation
...

## Rollback
...

## Known Quirks
...
```

In diff mode, replace the body below the header with a standard unified diff.

## Output Modes

- **FULL-WRITE** — emitted when no prior runbook exists at `docs/runbooks/<service>.md`. The full markdown document is produced for the user to save.
- **DIFF** — emitted when a runbook already exists at that path. A unified diff against the existing file is produced; additions reflect newly inferred alerts, dependencies, or user-supplied answers, and removals are proposed only when the source of truth (alert rule, manifest) has disappeared from the repo.

The user decides whether to apply either output. This skill never writes to the file system on their behalf.

## Rules

1. **Read-only** — never deploy, restart, scale, or roll back the service. Never run `helm upgrade`, `kubectl apply`, `terraform apply`, or `ansible-playbook` without `--check`.
2. **No fabrication** — dependencies, endpoints, thresholds, and on-call identities must be sourced from an observable file. Unknowns are marked `[needs input]`.
3. **Graceful SKIPPED** — if required CLIs (`helm`, `kubectl`, `promtool`) are missing, skip that inference step and note the gap rather than aborting.
4. **Verify-before-run discipline** — every first-response step ends with "verify before running in prod."
5. **Respect ownership** — if `CODEOWNERS` or equivalent assigns the service to a team, surface that team in the Escalation section verbatim.
6. **No secrets in output** — never echo connection strings, tokens, or credentials discovered in source; refer to them by variable name only.

$ARGUMENTS
