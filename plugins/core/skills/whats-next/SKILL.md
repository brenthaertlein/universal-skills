---
name: whats-next
description: Analyzes open issues, docs, and git history to recommend your next task. Interactive coaching flow.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion, Agent
---

# /whats-next

Analyze open issues, project docs, and contribution history to recommend the user's next task. Interactive coaching flow.

## Phase 1: Questionnaire

Ask the user what they are looking for BEFORE fetching any data. Use AskUserQuestion with all four questions in a single call:

**Q1 — Time availability:**
- Less than 1 hour (quick fix or config tweak)
- A few hours (focused session)
- Multi-session (spread across days)

**Q2 — Work type:**
- Feature work (new capabilities, enhancements)
- Maintenance & hardening (security, performance, cleanup, dependency updates)
- Documentation & planning (docs, architecture decisions, runbooks)
- Whatever needs attention most

**Q3 — Work style:**
- Something I can ship quickly
- A meaty challenge
- Fix something broken or incomplete
- Improve reliability / observability / security

**Q4 — Area preference:**
- Familiar territory (play to strengths)
- Stretch into something new
- A mix

Store answers for Phase 2 filtering.

## Phase 2: Gather Data

Run in parallel where possible:

### 2a. Fetch open issues (PRIMARY SOURCE)

```bash
gh issue list --state open --limit 30 --json number,title,labels,body,assignees,comments 2>/dev/null
```

If `gh` fails or returns nothing, fall back to docs scanning only. Do not stop or error out.

For each issue found, classify:
- **Size**: Quick win (< 1 hour), Medium (focused session), Large (multi-session)
- **Area**: Derive from labels, title keywords, or body content

### 2b. Scan docs/ for work items (SECONDARY SOURCE)

Look for project documentation that contains work items:

```bash
ls docs/ 2>/dev/null
```

If a `docs/` directory exists, scan for files containing actionable items — look for TODO, FIXME, "future work", "next steps", "planned", "roadmap", or "open questions" sections. Read relevant docs and extract work items.

If no `docs/` directory exists, skip gracefully.

### 2c. Check git history for recent work

```bash
git log --oneline -20
git log --all --oneline --since="2 weeks ago"
```

Understand what areas have been recently active to avoid recommending redundant work and to identify the user's recent focus areas.

### 2d. Check for stale branches

```bash
git branch -a --list "origin/*" | grep -v main | grep -v master | grep -v HEAD
```

Flag branches that might represent in-progress or abandoned work.

## Phase 3: Categorize & Present

Filter results based on Phase 1 answers. Show max 3 items per category. Omit empty categories entirely.

### Quick Wins

Tasks completable in under an hour. Small fixes, config tweaks, doc updates, closing known gaps.

| # | Source | Task | Area | Why it's quick |
|---|--------|------|------|---------------|

### High Value

Improvements that meaningfully enhance the project's reliability, capability, or quality.

| # | Source | Task | Area | Complexity | Impact |
|---|--------|------|------|-----------|--------|

Source column should reference the origin: `GH #42`, `docs/roadmap.md`, `stale branch: feat/xyz`, etc.

### Maintenance

Security improvements, dependency updates, cleanup, monitoring gaps, tech debt.

| # | Source | Task | Area | Notes |
|---|--------|------|------|-------|

## Phase 4: Coaching

Based on git history, provide a brief coaching summary (4-6 sentences):

1. **Recent focus areas**: What areas the user has been working in (derived from recent commit messages and changed directories)
2. **Well-covered areas**: Areas with the most recent activity
3. **Underserved areas**: Areas with little recent attention — frame positively as opportunities, not criticism

## Phase 5: Recommendation

Before committing to a recommendation, dispatch to the `engineering-lead` subagent with the categorized candidates (Quick Wins / High Value / Maintenance) and the user's stated preferences from Phase 1. Ask it to pick the single highest-leverage next task and justify why it beats the runners-up, weighing value, readiness, and the user's context. Use its pick to inform the recommendation below — you may override it, but say why if you do.

```
Agent({
  subagent_type: "engineering-lead",
  description: "Pick the next task",
  prompt: "Candidate work items: <Quick Wins, High Value, Maintenance lists with sources>. User preferences/context: <from the questionnaire>. Pick the ONE highest-leverage task to do next and justify why it beats the runners-up, weighing value, readiness, effort, and the user's stated context. Return the pick plus a one-line rationale for the top 2-3 alternatives."
})
```

Recommend ONE specific task. Match verbosity to complexity:

- **For quick wins**: 1-2 sentences, link to source
- **For medium tasks**: Why it fits the user's preferences, what to read first, relevant files
- **For large tasks**: Full breakdown with suggested approach, relevant skills (`/start-work`)

End with: "Want to start? I can run `/start-work` to draft a plan."

## Phase 6: Deep-Dive

If the user picks a task:

1. Read the source (issue body, doc section) in full
2. Search codebase for related files (Grep/Glob)
3. Summarize what needs to change
4. Suggest a 3-5 step approach
5. Offer to start: "Want me to begin? I'll run `/start-work` to create a branch and draft a plan."

## Rules

- **Read-only** — never modify code, docs, or configuration
- **GitHub issues are the PRIMARY source** of work items, docs/ is secondary
- If `gh` CLI fails, continue with docs-only mode — never stop or error out
- Do not read or display secrets
- Do not recommend work that is already covered by an open PR (cross-reference with `gh pr list` if available)
