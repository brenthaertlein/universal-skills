---
name: draft-postmortem
description: "Draft a blameless postmortem from incident evidence - logs, timeline, Slack/chat transcript, and deploy history."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
argument-hint: "<incident-id or path to evidence directory>"
---

# Draft Blameless Postmortem

Build a blameless postmortem draft from incident evidence - logs, chat transcripts, deploy events, and a user-supplied timeline - into a markdown document ready to paste into the org's incident doc store. This skill is **read-only** — it never posts to chat, mutates incident tracking tools, or publishes the draft anywhere.

## Invocation

The user runs `/draft-postmortem <incident-id or path>`. The argument is either:

- an incident identifier (e.g. `INC-1234`) used to label the document and search nearby evidence directories, or
- a filesystem path to a directory of collected evidence (logs, chat exports, deploy manifests, screenshots).

If the argument is omitted, prompt once with AskUserQuestion for the incident ID and an evidence path before proceeding.

## Execution Steps

### 1. Gather Evidence

Use AskUserQuestion to collect what the evidence files alone cannot tell you:

```
Question: "I need a few framing details before drafting."
Options:
  1. "Incident start (UTC)"
  2. "Incident end (UTC)"
  3. "Impacted services"
  4. "Severity (SEV1..SEV4)"
  5. "Links or paths to logs, chat, deploys, dashboards"
```

Collect answers field by field. If the user declines to provide a field, record `[needs input]` and continue — never fabricate a value. Then enumerate the evidence directory:

- `*.log`, `*.json`, `*.ndjson` — structured log exports.
- `slack-*.json`, `chat-*.txt`, `transcript*.md` — chat transcripts.
- `deploys*.csv`, `deploys*.json`, `*.release.yaml` — deploy history.
- `dashboard-*.png`, `grafana-*.png` — attached screenshots (reference by filename, do not attempt OCR).

### 2. Build Timeline

Correlate evidence into a unified timeline. Every row must use the exact format:

```
HH:MM UTC - <actor or system> - <event>
```

Rules for timeline construction:

1. Prefer absolute UTC timestamps; if a source only has local time, convert and note the source timezone inline.
2. Include deploy events, first-alert firing, paging events, first human action, mitigations attempted, mitigation success, all-clear.
3. If two sources conflict on a timestamp, list both with `(per <source>)` and mark the row `(conflict)`.
4. Never invent a timestamp. When an event is known but its time is not, write `HH:MM UTC [needs input]` for the time.

### 3. Identify Contributing Factors

Apply 5-whys to the proximate cause, then separate findings into three labeled layers:

- **Proximate cause** — the direct trigger (e.g. "Deploy at 15:42 UTC replaced the health-check path").
- **Contributing factors** — changes that made the failure possible or worse (e.g. canary coverage skipped this endpoint; alert grouped with noisy peer).
- **Latent conditions** — longstanding gaps surfaced by the incident (e.g. no automated rollback on the service; runbook URL in alert was 404).

Do not assign blame to individuals in any layer.

After producing the three layers, dispatch to the `principal-sre` subagent to critique the 5-whys analysis. Ask it to look for: short-circuited "why" chains, layer mis-assignment (calling a latent condition a proximate cause), and missing system conditions (rollback path, alert routing, change gating). Integrate its findings as additional rows in the appropriate layers; do not let it rewrite the postmortem voice or replace this skill's verdict labels.

```
Agent({
  subagent_type: "principal-sre",
  description: "Critique the 5-whys",
  prompt: "Review this incident's contributing-factor analysis: <proximate cause + contributing factors + latent conditions you produced>. Stress-test the 5-whys: where does the chain stop short? What system conditions made this failure possible that aren't yet listed? Return top findings in severity order."
})
```

The skill remains owner of the postmortem document and blameless framing. The agent only sharpens the contributing-factor analysis.

### 4. Draft Sections

Assemble the document with these sections in order:

1. `Summary` — 3-5 sentences covering what broke, for whom, for how long.
2. `Impact` — user-visible effect, revenue impact, SLO burn. Use `[needs input]` when data is missing; never estimate revenue.
3. `Timeline` — the table from step 2.
4. `Detection` — how the incident was first detected (alert, customer report, operator); time-to-detect.
5. `Response` — who paged, mitigations attempted in order, what worked.
6. `Root-cause analysis` — the three-layer output from step 3.
7. `What went well` — at least one item sourced from evidence; if nothing is evident, write `[needs input]`.
8. `What didn't go well` — sourced from evidence or chat transcript; no speculation.
9. `Action items` — table with columns `Item | Owner | Target date | Type`. Type is one of `prevent | detect | mitigate | document`. When owner or date is unknown, write `TBD`.

### 5. Blameless Check

Scan the completed draft and rewrite any sentence where a named person is the grammatical subject of a verb tied to the failure.

- "Alice deployed a broken change" - **A deploy at 15:42 UTC introduced a regression in the health-check path.**
- "Bob ignored the alert" - **The alert was acknowledged but not actioned; the runbook it linked to returned 404.**

Keep names only in neutral context (e.g. "IC: Alice; Comms: Bob" in the Response section). Flag remaining name-subject-verb patterns in a final `### Blameless review notes` section if any survived rewriting.

## Output Format

```
# Postmortem - <incident-id>

**Severity:** <SEV?>   **Status:** Draft
**Window (UTC):** <start> -> <end>   **Duration:** <HH:MM>
**Impacted services:** <list>

## Summary
...

## Impact
- Users: ...
- Revenue: [needs input]
- SLO burn: ...

## Timeline
| Time (UTC) | Actor / system | Event |
|------------|----------------|-------|
| 15:42 | deploy-bot | Release v1.42.0 rolled to prod |
| 15:48 | prometheus | HighErrorRate alert fired on api-svc |
...

## Detection
...

## Response
...

## Root-cause analysis
**Proximate cause:** ...
**Contributing factors:** ...
**Latent conditions:** ...

## What went well
...

## What didn't go well
...

## Action items
| Item | Owner | Target date | Type |
|------|-------|-------------|------|
| Add canary coverage for /healthz | TBD | TBD | prevent |
| Fix runbook URL in alert definition | TBD | TBD | detect |

### Blameless review notes
- <any remaining name-subject-verb sentences to revisit>
```

## Verdict

This skill produces a document, not a pass/fail gate. Close the report with one of the following readiness labels:

- **READY** — all sections populated from evidence, zero `[needs input]` markers, zero rows in `Blameless review notes`.
- **DRAFT** — at least one `[needs input]` marker or TBD owner, no blameless violations. Safe to circulate internally.
- **INCOMPLETE** — blameless review notes non-empty, or Timeline contains fewer than three rows, or Impact is entirely `[needs input]`. Do not circulate until resolved.

## Rules

1. **Read-only.** Never post to chat, update Jira/Linear, email, or publish the draft. Output is text only.
2. **Graceful skip.** If evidence files are missing, unreadable, or the user declines to supply framing details, mark the affected sections `[needs input]` and continue.
3. **No fabrication.** Never invent timestamps, actors, deploy versions, revenue figures, user counts, or action-item owners. Prefer `[needs input]` or `TBD`.
4. **Blameless framing.** Never assign failure to a named individual. Use system framing in every root-cause and contributing-factor sentence.
5. **Cite evidence.** Every timeline row must be traceable to a file in the evidence directory or to a user-supplied answer. Do not synthesize rows.
6. **No remediation commands.** The draft describes what to do; it does not run rollbacks, redeploys, or any mutating action.

$ARGUMENTS
