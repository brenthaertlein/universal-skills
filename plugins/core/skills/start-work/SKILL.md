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
gh pr list --head "<branch>" --json number,title,state,url
```

If an open PR exists, highlight it — the user may want to continue rather than start fresh.

### 2b. Find related commits:

```bash
git log --all --oneline --grep="<keyword>" -10
```

### 2c. Check for related issues:

```bash
gh issue list --state open --limit 10 --search "<keyword>" --json number,title,state,labels 2>/dev/null
```

### 2d. Search codebase for relevant files:

Based on the work item content, use Grep and Glob to find:
- Config files that would need changes
- Existing code in the same area
- Related files based on keywords from the work item

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

## Phase 5: Draft Plan

Create `.plans/` directory if needed, then write to `.plans/<slug>.md`:

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

Display the full plan, then present these options:

1. **Start implementation** — Work through each step interactively
2. **Start with auto edits** — Implement full plan, only pause for risky operations
3. **Chat about the plan** — Discuss before committing to it
4. **Revise with feedback** — Refine the plan based on user input
5. **Cancel** — Stop (plan file remains for later)

### Option 1 — Start implementation:

1. Check for existing branches, offer to reuse or create new from `origin/main`
2. `git fetch origin main && git checkout -b <branch> origin/main`
3. Work through each step, briefly summarize after each
4. If `superpowers:test-driven-development` is available, apply the TDD cycle for
   each implementation step — write the failing test first, verify it fails,
   implement minimum to pass, verify it passes.
5. Run project-defined checks after completing all steps
6. Do NOT commit — suggest `/commit` when ready

### Option 2 — Auto edits:

Same as Option 1 but only pause for:
- Destructive or risky operations
- Flagged decision points from the plan's "Risks & Open Questions"
- Anything requiring credentials or manual access

If `superpowers:test-driven-development` is available, apply the TDD cycle for each implementation step (same as Option 1).

### Option 3 — Chat about the plan:

Enter discussion mode. Answer questions, explain reasoning, adjust scope.

### Option 4 — Revise with feedback:

Accept feedback, update the plan file, re-present.

### Option 5 — Cancel:

Stop. Plan file remains at `.plans/<slug>.md` for later use.

## Safety Rules

- Always branch from latest `origin/main` (or the project's default branch)
- Never commit without being asked — suggest `/commit` when ready
- Never push without asking
- Never amend commits
- Respect existing branches — offer to reuse if an open PR exists
- Do not over-explore — Phase 3 should take 2-3 minutes, not 10
- Plan file is persistent — do not delete after implementation
- Batch edits — do not commit after every small change
- Never print or display secrets
- Respect any access rules or safety constraints defined in CLAUDE.md
