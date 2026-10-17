---
name: start-work
description: Research a work item, draft an implementation plan, and begin work after approval.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion, Agent, Edit, Write
---

# /start-work

Research a work item, draft an implementation plan, and begin work after approval.

## Supporting Skills Integration

All integrations below are strictly conditional on external plugins. If a skill is
not available, proceed as if this section does not exist — no mention, no complaint.

**After Phase 1d** (work item confirmed): if `core:scope-statement-check` is
available, run `scope-statement-check extract` on the work item to write a scope
contract to `.scope/<branch>.md`. This feeds downstream into commit
enforcement and pr-fix classification.

**Between Phase 2 and Phase 3**: if `feature-dev:feature-dev` or
`superpowers:brainstorming` is available, present a routing question before
codebase exploration. Include only the options whose skills are actually installed:

Use AskUserQuestion — "How do you want to approach this?":

- **Quick start** *(always present)* — codebase scan, questionnaire, plan (Phases 3–6)
- **feature-dev** *(only if `feature-dev:feature-dev` is available)* — parallel
  agent codebase exploration and architecture design; returns to you at implementation
- **Brainstorm** *(only if `superpowers:brainstorming` is available)* — design
  dialogue → spec doc → `writing-plans` → `subagent-driven-development`

If neither skill is available: skip the question entirely and proceed directly to Phase 3.

If **feature-dev** chosen: pass work item summary + Phase 2 findings as context,
invoke `feature-dev:feature-dev`. Do not proceed with Phases 3–6.

If **Brainstorm** chosen: pass work item summary as context, invoke
`superpowers:brainstorming`. Do not proceed with Phases 3–6.

Either route still owns the session journal: once the branch enters active use,
initiate it exactly as "Journaling the session" describes — no prompt.

## Phase 1: Parse Input & Fetch Context

Accept flexible input:
- `/start-work 42` — GitHub issue #42
- `/start-work docs/some-planning-doc.md` — work from a planning doc
- `/start-work search-feature` — fuzzy match against filenames, doc headings, and GH issue titles
- No argument — ask the user with AskUserQuestion: "What would you like to work on? (issue number, file path, keyword, or describe the task)"

### 1a. If GitHub issue number or URL:

```bash
gh issue view <number> --json number,title,body,labels,assignees,comments,state
```

Display issue summary: number, title, state, labels, and body excerpt.

If the issue is closed, warn the user and ask with `AskUserQuestion` whether to
proceed or cancel.

### 1b. If file path or keyword:

- Glob for `docs/*<keyword>*` and search filenames across the repo
- If multiple matches, present them and ask user to pick one
- Read the matched file
- Extract relevant sections: look for headings with the keyword, or "Next Steps", "Planned", "TODO", "Open Questions" sections
- Display summary of what the file describes and what work is outlined

### 1c. Identify repo context:

```bash
gh repo view --json nameWithOwner,url 2>/dev/null
```

### 1d. Display work item summary so the user can confirm the correct item before proceeding.

## Phase 2: Research Related Work

Run these in parallel:

### 2a. Find branches referencing the work item:

```bash
git branch -a --list "*<keyword>*"
```

For each matching branch, check PR status:
```bash
gh pr list --head "<branch>" --state all --json number,title,state,url
```

Classify each branch by its PR state:
- **Open** — active in-progress work. Highlight it prominently; the user may want to continue rather than start fresh.
- **Merged** — completed work. Do not offer it as a starting point.
- **Closed (not merged)** — abandoned work. Note it, but do not reuse it.

### 2b. Find related commits:

```bash
git log --all --oneline --grep="<keyword>" -10
```

For issue-based work, also grep for `#<number>` so commits that reference the issue are not missed.

### 2c. Check for related issues:

```bash
gh issue list --state open --limit 10 --search "<keyword>" --json number,title,state,labels 2>/dev/null
```

### 2d. Search codebase for relevant files:

Based on the work item content, use Grep and Glob to find:
- Config files that would need changes
- Existing code in the same area
- Related files based on keywords from the work item
- `TODO` / `FIXME` comments that reference the issue number

Present related work summary to the user.

## Phase 3: Codebase Exploration

Based on the work item, explore affected areas:

1. **Extract keywords** — service names, directory paths, function names, module names from the work item
2. **Grep for relevant code and config** — search for those keywords across the repo
3. **Glob for related files** in likely directories based on the project's structure
4. **Read 3-5 most relevant files** — understand current state
5. **Understand current state** — what exists, what is missing, what needs changing

Time-box this phase. Enough context for a solid plan, not an exhaustive audit. Aim for 2-3 minutes of exploration.

## Phase 4: Dynamic Questionnaire

Ask 2-4 targeted questions using AskUserQuestion. Generate these based on the specific work item — do not use generic questions. Examples of question types:

- **Scope**: "The issue mentions X and Y. Address both in one PR or split?"
- **Approach**: "This could be done with approach A or approach B. Preference?"
- **Depth**: "Minimal implementation first, or full production-ready with tests and error handling?"
- **Dependencies**: "This depends on [other item]. Should we handle that first or work around it?"
- **Compatibility**: "This touches shared code used by [other features]. How cautious should we be?"

Rules:
- Always ask at least 2 questions, never more than 4
- Each question should have 2-4 concrete options
- Questions must be specific to the work item, not boilerplate
- Never ask a question the issue, its comments, or CLAUDE.md already answers
- Never ask about required workflow steps (the session journal, worktree setup, baseline checks) — those are not decisions
- If the work item is straightforward and unambiguous, ask about scope depth and verification approach

## Phase 5: Draft Plan

### 5a. Validate the proposed branch name (soft check)

Before writing the plan file, validate the branch name you're about to record in the plan's `**Branch**:` field.

Propose `{type}/{number}-{slug}` for issue-based work (`{type}/{slug}` otherwise), where `{slug}` is a 2-4 word kebab-case summary of the title. Pick `{type}` from the nature of the work: `fix` for bugs and regressions, `feat` for new behavior, `docs`, `test`, `refactor` (no behavior change), `perf`, `chore` / `build` for deps and config, `ci` for pipelines. Never use an auto-generated name (e.g. `claude/<adjective>-<noun>-<hex>`) — always pass an explicit branch name.

**Default regex:** `^(feat|fix|chore|docs|refactor|test|perf|build|ci|style)/(?:[0-9]+-)?[a-z0-9][a-z0-9-]*$`

Matches: `feat/new-feature`, `fix/123-broken-button`, `chore/update-deps`, `refactor/auth-cleanup`. Does NOT match: `my-feature` (no type prefix), `Feat/X` (uppercase), `feat_x` (underscore instead of slash).

**Soft check only.** If the proposed branch name doesn't match the active regex, present an `AskUserQuestion` with three options:
- **Use the suggested compliant name** — derive one by lowercasing, replacing spaces/underscores with `-`, and prepending a sensible type prefix inferred from the work item (issue label, PR-style commit prefix in related work, or default to `feat`)
- **Override with this name (continue anyway)** — record the non-compliant name and proceed
- **Pick another name** — ask the user for a replacement

Never reject silently. Never block.

**Configurable via CLAUDE.md key `start-work.branch-pattern`:**
- `<regex string>` — override the default with a project-specific regex.
- `disabled` — skip the check entirely.
- Omitted — use the default regex above.

### 5b. Write the plan file

Create `.plans/` directory if needed, then write to `.plans/<slug>.md`. Use the same `<slug>` as the branch (with the issue number prefix, minus the type prefix — e.g. `fix/42-auth-redirect` → `.plans/42-auth-redirect.md`) so plan and branch are easy to correlate:

```markdown
# Plan: <Title>

**Source**: [#42](url) or [docs/file.md](path)
**Branch**: `<proposed-branch-name>`
**Date**: <today>

## Context

<2-3 sentence summary incorporating research findings and user's questionnaire answers.>

### Related Work
- Branch: `<name>` (if exists)
- Related issues: <list>
- Related files: <list>

### User Decisions
- <Q1 summary>: **<Answer>**
- <Q2 summary>: **<Answer>**

## Requirements

Extracted from the issue/doc and questionnaire:

1. <Requirement>
2. <Requirement>

## Implementation Steps

### Step 1: <title>
- **Files**: `path/to/file`
- **What**: <description>
- **Why**: <reasoning>
- **Verify**: <how to validate this step>

### Step 2: <title>
...

### Step N: Verify
- Run project-defined checks (see /commit preflight)
- <Manual verification steps if applicable>
- <Specific commands to verify the changes work>

## Files to Modify

| File | Action | Reason |
|------|--------|--------|
| `docs/issues/<number>-<slug>.md` (or `docs/issues/<slug>.md` without an issue) | Create/Modify | Session journal (see "Journaling the session") |
| `path/to/file` | Create/Modify | <reason> |

## Verification

How to test end-to-end:
1. <Step-by-step>
2. <What to check>

## Risks & Open Questions

- <Uncertainties>
- <Side effects>
- <Decision points during implementation>
```

## Phase 6: Present Plan & Prompt

Display the full plan, then present these options **using `AskUserQuestion`**
("How do you want to proceed?"). Do not render them as a prose list — this is a
pick-one-of-N next-action choice, exactly what `AskUserQuestion` is for. Each
option maps to a handler section below:

- **Start implementation** — work through each step interactively (Option 1)
- **Start with auto edits** — implement the full plan, pausing only for risky operations (Option 2)
- **Chat about the plan** — discuss before committing to it (Option 3)
- **Revise with feedback** — refine the plan based on your input (Option 4)
- **Cancel** — stop; the plan file remains for later (Option 5)

### Journaling the session (Options 1 & 2)

`/start-work` opens the working journal that `/document` formalizes. The journal
is a **required** part of the workflow, not an optional extra — create it without
asking. Treat it as a **living document**: seeded with intent here, grown with
decisions as work progresses, and finalized with outcomes at `/pr-fix` and
`/ship-it`. `/document` remains the source of truth for the doc *format*; this
skill seeds the file, it does not restate the template.

**When the branch enters active use — whether newly created or an existing one
being resumed — before working any step**, initiate the journal. Do not ask
first; this is a required step, not a decision:

1. Resolve the journal path:
   - **Issue-based work** — look for an existing `docs/issues/{number}-*.md`.
     Match on the issue number, not an exact slug: `/document` may have created
     the doc with a different slug. If none exists, the path is
     `docs/issues/{number}-{slug}.md`, with `{slug}` derived from the issue title
     (kebab-case, 2-4 words) per `/document`'s convention.
   - **No issue** (planning doc, keyword, or free-text task) — the path is
     `docs/issues/{slug}.md`, using the plan's `<slug>` from Phase 5b. Match an
     existing doc on that exact slug.
2. If a doc exists at that path, reuse it and append to it. Otherwise create it
   immediately, using `/document`'s issue-doc format as the template. Seed it
   with the session intent from the approved plan — what this work is, why, and
   the approach chosen — populated from the work item (issue body and comments,
   or the source doc / task description), Phase 3 exploration, and Phase 4
   answers, leaving room for a running work log and a final outcomes section.
3. For **software / feature work**, also bring the `docs/features/` entry for the
   area being changed up to date, delegating format and creation to `/document`:
   create `docs/features/{name}.md` for a new feature or an enhancement to an
   undocumented one; update the existing concept doc for an enhancement to a
   documented one. Skip this entirely for skill, documentation, or
   CI/config-only changes — `/document` excludes those, so there is nothing to
   document as a feature.

As you work through the plan's steps, append the meaningful decisions, approaches
considered, and rationale (developer and AI) to the journal — the *why*, not just
the diff. This running work log is what the journal exists to hold.

### Option 1 — Start implementation:

1. Set up an isolated worktree — never switch branches in the main working tree:
   - If Phase 2 found an existing branch with an **open** PR, reuse it via the
     `/checkout` flow (`.worktrees/<branch-with-slashes-as-dashes>`).
   - Otherwise, create a fresh branch from the latest default branch:
     ```bash
     git fetch origin main
     ```
     ```bash
     git worktree add .worktrees/<branch-with-slashes-as-dashes> -b <branch> origin/main
     ```
     `cd` into the worktree, then copy env files and install dependencies as
     `/checkout` steps 4-5 describe — both assume the worktree is the current
     directory.
   - If the worktree already exists, use it — never delete or recreate it.

   All subsequent work happens inside the worktree.
2. Transfer this task's untracked artifacts into the worktree — `git worktree add`
   does not carry gitignored files, and `/commit` and `/pr-fix` look for them
   relative to the worktree:
   - `.plans/<slug>.md` (the approved plan)
   - `.scope/<branch>.md` (the scope contract, if one was extracted)

   Copy each from the main checkout to the same relative path in the worktree.
   If the worktree already has a copy that differs, ask with `AskUserQuestion`
   which version to keep — never overwrite it silently. Afterwards, edit only
   the worktree's copy.
3. Run the project's checks as a baseline (see `/commit` preflight). If they
   already fail, report the failures and ask with `AskUserQuestion` whether to
   proceed or investigate first — so pre-existing failures are not later
   mistaken for regressions.
4. Initiate the session journal — see "Journaling the session (Options 1 & 2)" above.
5. Work through each step, briefly summarize after each — and record meaningful
   decisions, approaches considered, and the rationale behind developer + AI
   choices in the session journal as you go.
6. If `superpowers:test-driven-development` is available, apply the TDD cycle for
   each implementation step — write the failing test first, verify it fails,
   implement minimum to pass, verify it passes.
7. Run project-defined checks after completing all steps
8. Do NOT commit — suggest `/commit` when ready

### Option 2 — Auto edits:

Same setup as Option 1 (worktree, artifact transfer, baseline checks, session journal), then
implement every step without pausing, except for:
- Destructive or risky operations
- Flagged decision points from the plan's "Risks & Open Questions"
- Anything requiring credentials or manual access

If `superpowers:test-driven-development` is available, apply the TDD cycle for each implementation step (same as Option 1).

Run project-defined checks at the end. If they fail, attempt to fix the
failures, then present a summary of all changes made. Do NOT commit — suggest
`/commit` when ready.

### Option 3 — Chat about the plan:

Enter discussion mode. Answer questions, explain reasoning, adjust scope. When
the user is ready to proceed, re-present the Phase 6 options.

### Option 4 — Revise with feedback:

1. Collect feedback with `AskUserQuestion`, offering common revision types
   ("Narrow the scope", "Change the approach", "Add more detail") alongside
   free text.
2. Update the plan file with `Edit`, then re-display the plan and re-present the
   Phase 6 options.
3. After 3 revision cycles, suggest the user edit the plan file directly.

### Option 5 — Cancel:

Stop. Plan file remains at `.plans/<slug>.md` for later use.

## Safety Rules

- Always branch from latest `origin/main` (or the project's default branch)
- Always use a worktree under `.worktrees/` — never switch branches in the main working tree, which must stay on the default branch
- Never commit without being asked — suggest `/commit` when ready
- Never push without asking
- Never amend commits
- Never run destructive operations (`rm -rf`, `git reset --hard`, `git checkout .`) without an explicit user request
- Respect existing branches — offer to reuse one only when it has an **open** PR; for merged or closed PRs, always start a fresh branch from `origin/main`
- Do not over-explore — Phase 3 should take 2-3 minutes, not 10
- Plan file is persistent — do not delete after implementation
- Maintain the session journal — `docs/issues/{number}-*.md` (or `docs/issues/{slug}.md` without an issue) is a living
  record of intent, decisions, and outcomes; keep it current as work progresses
  (see "Journaling the session"). Required: create it without asking.
- Batch edits — do not commit after every small change
- Never print or display secrets
- Respect any access rules or safety constraints defined in CLAUDE.md
