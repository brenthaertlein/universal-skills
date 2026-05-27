---
name: scope-statement-check
description: "Extract a scope contract from an issue or spec, enforce it at commit time, and use it to classify out-of-scope review feedback."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---

# Scope Statement Check

A staff-engineer habit, encoded. Before you start work, write down what the work *is* and *isn't*. Then let that contract decide which review feedback you address and which you defer with a one-line rationale.

The single highest-leverage pattern from teams that ship cleanly: **the scope of an issue is decided at start-of-work, not at code-review-time.**

## Invocation

- `/scope-statement-check extract <issue-or-doc>` — extract a scope contract from an issue number, URL, or file path
- `/scope-statement-check enforce` — diff staged changes against the active contract
- `/scope-statement-check classify` — classify a list of review findings against the active contract
- `/scope-statement-check show` — print the active contract for this branch

## Modes

### 1. Extract — at start of work

Build the contract from the source of truth and persist it.

#### Inputs
- A GitHub issue number/URL: fetch via `gh issue view <n> --json title,body,labels`
- A local file (spec, design doc, ticket export): read directly
- A free-text description: prompt the user for the scope statement

#### What to extract
Scan the source for these signals, in order of preference:

1. An explicit **"Scope:"**, **"In scope:"**, or **"Out of scope:"** heading or bullet list
2. An **acceptance criteria** section
3. The **first paragraph's verb cluster** (what the work *does*) and **constraints** ("only", "without", "must not")
4. **Linked issues** referenced as "follow-up", "tracked separately", "out of scope for this issue"

If none of those exist, run an `AskUserQuestion` with two questions:
- "What does this issue change?" (single-select among the top three plausible scopes)
- "What is explicitly excluded?" (free text)

#### Contract format
Write to `.scope/<branch-name>.md`:

```markdown
# Scope Contract — <Title>

**Source**: <issue URL or file path>
**Branch**: <branch name>
**Extracted**: <ISO date>

## In Scope
- <verb-led bullet>
- <verb-led bullet>

## Out of Scope
- <verb-led bullet> — defer to <follow-up issue or "future work">
- <verb-led bullet>

## Touched Surfaces
Files or directories this work is allowed to modify:
- `path/glob/**`
- `another/path/**`

## Untouched Surfaces
Files or directories that should NOT change in this work:
- `path/glob/**`

## Notes
<Any constraints, dependencies, or known follow-ups>
```

Verb-led bullets read like instructions, not descriptions: "**Add** a retry header" beats "Retry header should be added". Verbs make scope decisions easy at commit time.

If the source explicitly excludes a directory, list it under **Untouched Surfaces**. If the source doesn't mention a surface, leave the list inclusive — `Untouched` is a hard constraint, not a guess.

### 2. Enforce — at commit time

Run after staging, before `/commit`. Compare the staged diff to the contract.

#### Steps
1. Load `.scope/<branch>.md`. If missing, prompt: "No scope contract for this branch. Extract one now, or proceed without?" Default to extract.
2. List files in the staged diff: `git diff --cached --name-only`
3. For each file, classify against the contract:
   - **In contract** — file matches a `Touched Surfaces` glob → OK
   - **Outside contract** — file matches an `Untouched Surfaces` glob → BLOCK
   - **Unclassified** — file matches neither → WARN

#### Block / warn output
For each finding, print:
- The file path
- Which contract section it violates (or that it's unclassified)
- A specific action: "Move to a separate branch", "Expand the contract with rationale", "Split into a follow-up"

Use `AskUserQuestion` with these options when violations exist:
- **Split into a separate branch** — stash these changes and continue
- **Expand the contract** — add the file's surface to `Touched Surfaces` with a one-line rationale appended to the contract's `Notes` section
- **Proceed anyway** — record an override in the contract under a `## Overrides` section with the user's reason

### 3. Classify — at PR feedback time

Used by `pr-fix` (or any review-triage workflow) to auto-bucket out-of-scope items.

#### Input
A list of review findings, each with `path`, `line`, `body`.

#### Output
For each finding, attach a `scope_classification`:
- **in-scope** — `path` is inside `Touched Surfaces` *and* the finding's subject relates to a `In Scope` bullet
- **out-of-scope-surface** — `path` is in `Untouched Surfaces` or outside both lists
- **out-of-scope-subject** — `path` is in scope but the finding addresses something the contract explicitly excluded (e.g., "consider migrating to X" when the contract says "no migration")
- **ambiguous** — neither clearly in nor clearly out; leaves the decision to the human

#### Generated rationale
For out-of-scope findings, generate the deferral reply text:

```
Deferring — this is outside the scope of <issue/branch>: <one-line contract reference>.
Tracking separately: <suggested follow-up issue link or note>.
```

The user reviews and edits before posting. The goal is to remove the keystroke cost of typing the same rationale across many comments; the *judgment* stays human.

### 4. Show

Print the active contract. No flags. If there is no contract for the current branch, say so and suggest `extract`.

## Integration Points

This skill is most useful when wired into adjacent workflows. The integration is **documented, not automatic** — invoke explicitly until the team is confident.

- **`start-work`**: after the work item is fetched, run `extract` on it before generating the implementation plan. The plan's "Requirements" section should mirror the contract's "In Scope".
- **`commit`**: run `enforce` before staging. A blocked file does not stop the commit; it forces the user to acknowledge the override.
- **`pr-fix`**: run `classify` on the fetched review findings before presenting the matrix. The classification appears as an extra column.

## Rules

- The contract is a *contract*, not a *plan*. It states what changes and what doesn't, not how.
- Verb-led bullets only. "Refactor logging" is a description; "Replace `console.log` calls in the upload pipeline with the project logger" is a contract.
- Out-of-scope items are tracked, not lost. Each one should name a follow-up or be tagged "future work".
- Overrides are recorded with rationale. Silent expansion of scope is what the contract exists to prevent.
- The contract belongs to the branch, not the issue. A single issue may produce multiple branches; each has its own contract.
- Never delete a contract file. When the branch merges, the contract is the artifact of the decision.

## Why this exists

The single most common form of review-cycle waste is bots and reviewers flagging legitimate improvements that the author intentionally chose not to make in this branch. Without a contract, every deferral is a fresh argument. With a contract, every deferral is a one-line reference to a decision already made.

Senior engineers do this implicitly — they hold the scope in their head and defer with confidence. The skill makes the implicit explicit so the same discipline survives across collaborators, agents, and reviews months later.
