---
name: review-observability
description: "Audit a service for logging, metrics, and tracing coverage. Flags missing RED/USE signals, alerts without runbooks, dashboards without owners."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Agent
argument-hint: "<service path>"
---

# Observability Coverage Review

Audit a service's observability surface — structured logs, metrics, traces, alerts, and dashboards — and report coverage gaps against the RED (Rate/Errors/Duration) and USE (Utilization/Saturation/Errors) models. This skill is strictly **read-only**; it inspects source code and configuration artifacts only and never emits telemetry, scrapes endpoints, or mutates monitoring backends.

## Invocation

The user runs `/review-observability <service path>`. The argument is the path to the service's source directory. If omitted, scan the repo root and ask the user to narrow scope when more than one service is detected.

## Execution Steps

Execute each step in order. Record every finding with a file path and line reference so reviewers can audit the source.

### 1. Detect Stack

Identify the observability tooling already wired in:

- **Metrics** — `prometheus_client`, `micrometer`, `opencensus`, `statsd`, `/metrics` endpoint exposure, CloudWatch EMF, GCP `opentelemetry-exporter-gcp`.
- **Logging** — structured loggers such as `zap`, `logrus`, `zerolog`, `structlog`, `winston`, `bunyan`, `pino`, `serilog`, `log4j2` with JSON layout.
- **Tracing** — OpenTelemetry SDKs (`@opentelemetry/*`, `opentelemetry-*`), Jaeger/Zipkin clients, AWS X-Ray SDK, Datadog APM.
- **Platform signals** — CloudWatch agent, Ops Agent, Fluent Bit, Vector, OTel Collector configs.

If no instrumentation is detected, record the stack as `NONE` and continue — every later step will surface gaps.

### 2. Score RED for Request Handlers

Enumerate every request entry point:

- HTTP route handlers (framework-specific: Express, FastAPI, Gin, Spring, Rails).
- gRPC service methods.
- Queue consumers and stream processors.
- Scheduled/cron handlers (treated as a degenerate "rate = 1/interval").

For each handler, score:

- **Rate** — is a counter or histogram incremented per invocation?
- **Errors** — is there a distinct error counter, or an error-status label on the rate metric?
- **Duration** — is a histogram/summary observing request latency?

List gaps per handler. A handler missing any RED signal is a finding.

### 3. Score USE for Resources

Enumerate declared resources the service owns:

- Database connection pools.
- Cache clients (Redis, Memcached).
- Worker pools, thread pools, goroutine pools.
- Message queue consumers with prefetch limits.
- File handle / socket limits if declared.

For each resource, score:

- **Utilization** — is current in-use quantity exported?
- **Saturation** — is the wait-time or queue-depth exported?
- **Errors** — are resource-scoped errors distinct from request-scoped errors?

Gaps surface as findings per resource.

### 4. Audit Alerts

For every alert definition in the repo (Prometheus rules, CloudWatch alarms, GCP alert policies, Grafana alerts):

- Does the alert reference a runbook URL or annotation? Missing runbook = finding.
- Does the metric it fires on exist in the code scanned in Steps 1–3? A missing metric is a broken alert.
- Is there a severity label, and does it match the escalation policy style in use?
- Is the `for:` / evaluation duration set, or does the alert risk flapping?

After enumerating the alert findings, dispatch to the `principal-sre` subagent to score alert maturity. Ask it to apply its on-call lens — is each alert actionable at 3am, runbook-linked, owner-attributed, and unlikely to be noise? Receive back a prioritized list of weak alerts and integrate them into the Alerts section below; do not let it replace this skill's verdict labels.

```
Agent({
  subagent_type: "principal-sre",
  description: "Score alert maturity",
  prompt: "Review these alert definitions: <alert names, metrics, thresholds, runbook annotations, severity labels, for: durations>. Score each on noise risk, runbook quality, and owner clarity. Which would you snooze first as on-call? Return top findings in severity order."
})
```

### 5. Audit Dashboards

For every dashboard JSON or declarative dashboard (Grafana, CloudWatch, GCP Monitoring):

- Is an owner declared via tag, folder, or `meta` field? An unowned dashboard is a finding.
- Do its panels reference metric names that were discovered in Step 1? Orphan panels are findings.
- Are variables/templates tied to labels that the metrics actually expose?

## Output Format

```
## Observability Review — <service>

**Stack detected:** metrics=<tool>, logs=<tool>, traces=<tool>, platform=<agent>

### RED coverage (request handlers)
| Handler | Rate | Errors | Duration | Gaps |
|---------|------|--------|----------|------|
| POST /orders | yes | yes | no | add latency histogram |
...

### USE coverage (resources)
| Resource | Utilization | Saturation | Errors | Gaps |
|----------|-------------|------------|--------|------|
| db.pool.primary | yes | no | no | pool-wait + pool-errors missing |
...

### Alerts
- [FINDING] HighLatencyOrders — no runbook annotation (rules/orders.yml:42)
- [FINDING] CacheMissRateHigh — metric `cache_miss_total` not found in code
- [OK] ErrorBudgetBurnFast — runbook + metric verified

### Dashboards
- [FINDING] orders-overview.json — no owner declared
- [OK] orders-slo.json — owner=team-orders, panels resolved

### Summary
- RED gaps: N handlers
- USE gaps: N resources
- Alert findings: N
- Dashboard findings: N

**Verdict:** <WELL-COVERED | PARTIAL | BLIND>
```

## Verdict

- **WELL-COVERED** — every request handler has full RED, every declared resource has full USE, all alerts have runbook annotations and live metrics, and every dashboard has an owner.
- **PARTIAL** — at least one RED or USE signal is missing, or at least one alert lacks a runbook, or a dashboard is unowned, but core request-path signals (rate and errors on every handler) are present.
- **BLIND** — any of the following: no metrics stack detected at all, more than half of handlers missing any RED signal, or alerts firing on metrics that do not exist in the code.

## Rules

1. **Read-only** — never curl `/metrics` endpoints, query Prometheus, or call cloud monitoring APIs. Inspect declarations only.
2. **Graceful SKIPPED** — if `promtool`, `amtool`, or a dashboard validator is unavailable, skip syntactic validation and rely on grep-level inspection; record the tool as SKIPPED.
3. **No fabricated metric names** — only list metrics that appear verbatim in the code or declared in rules files. Inconclusive findings are marked `[INCONCLUSIVE]`.
4. **Respect language idioms** — a Rust service using `tracing` crate spans is not "missing logs" just because it lacks a Node-style JSON logger.
5. **Link, don't duplicate** — when an alert gap overlaps with `draft-runbook` scope, note it and defer details to that skill.
6. **Never propose code** — output findings only; remediation is the owning team's job.

$ARGUMENTS
