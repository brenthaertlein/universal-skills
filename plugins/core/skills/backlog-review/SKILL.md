---
name: backlog-review
description: Triage open issues for staleness, duplicates, missing context, and mis-labels; post review comments without mutating issue state.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, AskUserQuestion
argument-hint: [optional natural-language filter, e.g. "updated in the last week" or "label:bug"]
---

# Backlog Review

Triage the open-issue backlog: classify into **Stale**, **Duplicate candidate**, **Unclear**, **Mis-labeled**, and **Healthy** buckets, present a dashboard, and optionally post canonical triage comments on flagged issues.

Read-and-comment only. This skill never closes issues, edits issue bodies, changes labels, or modifies assignees. Mutating actions belong to the user or `/improve-issues`.

## How to use

- `/backlog-review` — prompts for scope (label, age, milestone) via `AskUserQuestion`.
- `/backlog-review <natural-language filter>` — parses the filter from the argument. Examples:
  - `/backlog-review issues updated in the last week`
  - `/backlog-review label:bug`
  - `/backlog-review milestone:v2`
  - `/backlog-review assignee:none label:enhancement`

Anything the parser can't resolve falls back to `AskUserQuestion` rather than guessing.

## Phase 1: Resolve scope

If an argument is present, parse it into a concrete `gh issue list` query:

| Phrase | Query fragment |
|--------|----------------|
| `label:<name>` or `--label <name>` | `--label "<name>"` |
| `milestone:<name>` | `--milestone "<name>"` |
| `assignee:none` / `assignee:@me` / `assignee:<login>` | `--assignee "<value>"` |
| `updated in the last <N> <unit>` | `--search "updated:>$(date offset)"` |
| `created in the last <N> <unit>` | `--search "created:>$(date offset)"` |
| `older than <N> <unit>` | `--search "updated:<$(date offset)"` |

If no argument is present, ask via `AskUserQuestion` (single call, multiple questions):

- **Label** — multi-select from `gh label list`; "any" allowed.
- **Age window** — Last 7 days / Last 30 days / Older than 8 weeks / Any.
- **Milestone** — single-select from `gh api repos/{owner}/{repo}/milestones --jq '.[].title'`; "any" allowed.

Echo the resolved filter back to the user before fetching.

## Phase 2: Fetch

```bash
gh issue list --state open \
  --json number,title,body,labels,assignees,createdAt,updatedAt,comments,milestone,url \
  --limit 100 \
  <filter flags from Phase 1>
```

If the result is empty, print "No open issues match this scope." and stop.

If `gh` is not authenticated or the working directory is not a GitHub repo, report the error clearly and stop — do not fall back to local-only analysis (unlike `/whats-next`, this skill is meaningless without the issue list).

## Phase 3: Analyze in parallel

If **4 or more** issues were fetched, dispatch one `Agent` per issue (`subagent_type: "Explore"`, max 3 concurrent) to classify each issue into one of the buckets below. For < 4 issues, classify inline.

### Bucket criteria

| Bucket | Condition |
|--------|-----------|
| **Stale** | No updates in ≥ 8 weeks **and** no open PR linked from the issue or its branch refs |
| **Duplicate candidate** | Title or body has high overlap with another open issue (or a closed-in-the-last-30-days issue); cite the candidate |
| **Unclear** | Body < 200 chars **or** missing acceptance criteria / repro steps **or** title is vague ("fix the thing", "broken") |
| **Mis-labeled** | Label conflicts with content — e.g. labeled `bug` but reads as a feature ask; labeled `priority: high` but no activity in months |
| **Healthy** | Clear, recent, has acceptance criteria or actionable description, labels match content |

An issue can belong to **at most one** bucket. Priority order if multiple match: Duplicate → Unclear → Mis-labeled → Stale → Healthy.

For each non-healthy issue, generate a one-line **recommendation**:

- Stale → `Comment: still wanted? (no activity since <YYYY-MM>)`
- Duplicate candidate → `Comment: looks like a duplicate of [#N](url)`
- Unclear → `Comment: needs acceptance criteria + repro` (or specifics)
- Mis-labeled → `Recommend: re-label as <suggestion> via /improve-issues`

### Linking convention

Always render issue references as markdown hyperlinks: `[#N](https://github.com/<owner>/<repo>/issues/N)`. Repo URL comes from `gh repo view --json url`.

### Time format

Use relative time in dashboards: `2w`, `3mo`, `1y` (same convention as `/project-status`).

## Phase 4: Present the dashboard

```markdown
# Backlog Review — <repo name>
**Scope**: <resolved filter>  |  **Open issues in scope**: N
**Stale**: N  |  **Duplicate candidates**: N  |  **Unclear**: N  |  **Mis-labeled**: N  |  **Healthy**: N

## Stale
| Issue | Title | Age | Last updated | Labels | Recommendation |
|-------|-------|-----|--------------|--------|----------------|
| [#N](url) | <title> | 5mo | 2025-12-14 | bug, area: api | Comment: still wanted? |

## Duplicate candidates
| Issue | Title | Likely duplicate of | Recommendation |
|-------|-------|---------------------|----------------|
| [#N](url) | <title> | [#M](url) | Comment: looks like a duplicate of [#M](url) |

## Unclear / underspecified
| Issue | Title | Missing | Recommendation |
|-------|-------|---------|----------------|
| [#N](url) | <title> | Acceptance criteria, repro | Comment: needs acceptance criteria + repro |

## Mis-labeled
| Issue | Title | Current label | Suggested | Recommendation |
|-------|-------|---------------|-----------|----------------|
| [#N](url) | <title> | bug | enhancement | Recommend: re-label via /improve-issues |

## Healthy
N issues — listed by issue number only: [#A](url), [#B](url), [#C](url), …
```

Omit any section whose count is zero (replace with a single line: `No stale issues found.`, etc.).

### Senior prioritization (dispatch)

After building the dashboard, dispatch to the `engineering-lead` subagent with the bucketed issues. Ask it to rank which issues most deserve action now — by value, readiness, and cost of delay — and which can wait. Present its ranked shortlist as a "Recommended order of action" block beneath the dashboard. It advises on prioritization only; it does not replace the bucket classifications above or post anything.

```
Agent({
  subagent_type: "engineering-lead",
  description: "Prioritize backlog buckets",
  prompt: "Here is a triaged backlog: <stale / duplicate / unclear / mis-labeled issues with titles, ages, and labels>. Rank the handful that most deserve action now versus later, by value, readiness, and cost of delay. For each, give a one-line rationale and the recommended action (close, groom, re-label, keep). Return a short ordered list."
})
```

## Phase 5: Offer to post triage comments

For Stale / Duplicate / Unclear buckets, ask via `AskUserQuestion`:

> Post triage comments? You can pick which buckets to act on.

Multi-select options: **Stale (N issues)** / **Duplicate candidates (N)** / **Unclear (N)** / **None — just the dashboard**.

For each bucket the user selects, post one comment per issue using the canonical marker (mirrors `/improve-issues`):

```markdown
## Backlog Review
<!-- backlog-review automated comment; do not edit this line -->

<bucket-specific note>
```

Bucket-specific note templates:

- **Stale** — `No activity since <YYYY-MM> and no linked PR. Is this still wanted? Closing in a future triage pass if it stays quiet.`
- **Duplicate candidate** — `This looks like a duplicate of [#M](url). Closing here once confirmed; please add any unique context to [#M](url) first.`
- **Unclear** — `Triage notes: this issue is missing <specifics — e.g. acceptance criteria, reproduction steps, affected version>. A quick update would help anyone picking it up.`

### Idempotency — never duplicate triage comments

Before posting, check for an existing backlog-review comment on the issue:

```bash
gh api repos/{owner}/{repo}/issues/{number}/comments \
  --jq '[.[] | select(.body | contains("<!-- backlog-review automated comment"))]'
```

- If none exists → `gh issue comment {number} --body "$(cat <<'EOF' ... EOF)"`.
- If one exists and the new note differs → `gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id}` to update it in place.
- If one exists and the new note matches → skip (no-op; report as "already up to date").

Mis-labeled issues do **not** get an automated comment from this skill — re-labeling is a `/improve-issues` job. Surface them in the dashboard and recommend the hand-off.

After posting (or skipping) every selected comment, print a summary:

```markdown
### Triage comments
| Issue | Bucket | Action |
|-------|--------|--------|
| [#N](url) | Stale | Posted new comment |
| [#M](url) | Unclear | Updated existing comment |
| [#K](url) | Stale | Already up to date — skipped |
```

## Phase 6: Interactive follow-up

After the dashboard (and optional comment pass), ask via `AskUserQuestion`:

> What would you like to do next?

Options:

1. **Dive into an issue** — prompt for an issue number, then show the full body + comments inline.
2. **Hand off to `/improve-issues`** — list flagged issue numbers (Unclear + Mis-labeled) for the user to run `/improve-issues <number>` on.
3. **Re-run with a different scope** — loop back to Phase 1.
4. **Done** — exit.

## Rules

- **Read + comment only.** Never `gh issue close`, `gh issue edit`, `gh issue lock`, `gh issue transfer`, or any label/assignee/milestone mutation. The dashboard and comments are the only outputs.
- **Confirm before posting any comment.** Silence is never approval.
- **Canonical marker on every triage comment** — `<!-- backlog-review automated comment; do not edit this line -->`. Subsequent runs update in place rather than appending duplicates.
- **One triage comment per issue, max.** If an older comment exists with a superset of the new content, leave it alone.
- **One `gh` call per Bash invocation.** Mirror the repo's never-chain-git rule.
- **Relative-time format in dashboards** — `2w`, `3mo`, `1y`. Reserve absolute dates for the "Last updated" column.
- **Markdown links for every issue/PR reference.**
- **Mis-labeled bucket never auto-comments.** Hand off to `/improve-issues`.
- **Healthy bucket is informational** — listed by number only; no comments, no recommendations.
- **If `gh` is unavailable, stop.** This skill needs the GitHub API; do not fall back to local-only analysis.
