---
name: new-issue
description: Draft and open a structured GitHub issue from a rough idea, with clarifying Q&A, labels, and type.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, AskUserQuestion
argument-hint: [rough idea, or blank to start interactively]
---

# New Issue

Draft and open a well-structured GitHub issue from a rough idea: clarifying Q&A, codebase context, duplicate detection, labels, and issue type — then `gh issue create` after explicit confirmation.

Sibling to `/improve-issues`: that skill enriches *existing* issues; this one authors *new* ones with the same level of care.

## How to use

- `/new-issue <rough idea>` — expand a one-line seed into a full issue.
- `/new-issue` — fully interactive; the skill prompts for the seed.
- `/new-issue --batch` — loop, drafting multiple issues in one session.

Examples:

```
/new-issue add dark-mode toggle to settings
/new-issue dashboard times out when org has > 500 projects
/new-issue --batch
```

## Workflow

### 1. Capture intent

If an inline argument is present, treat it as the seed. Otherwise, ask via `AskUserQuestion`:

> What problem or change does this issue describe? (one to three sentences)

Classify the seed as **problem-first** or **solution-first**. If the seed is solution-first ("add X button"), gently surface the underlying problem in step 2 — issues read better when they describe the problem before proposing a fix.

### 2. Clarify via `AskUserQuestion`

Ask the following questions in a single `AskUserQuestion` call (multiple questions, one round-trip):

- **Type** — Bug / Feature / Chore / Docs / Refactor / Question
- **Affected area** — code path, plugin, command, hook (free-text — used for `Grep`/`Glob` in step 3)
- **Acceptance criteria** — one to three testable bullets describing "done"
- **Suggested labels** — multi-select from existing repo labels (fetched via `gh label list --json name --jq '[.[].name]'`); offer "none" as a valid choice

If the user cannot articulate acceptance criteria, note this — do **not** invent them. The drafted issue will include a `Needs acceptance criteria` note in the body and a `needs-triage` label suggestion.

### 3. Gather repo context

Use `Grep` / `Glob` against the affected area to surface concrete file references:

- Mentioned filenames, functions, commands → exact paths + line numbers
- Mentioned modules, components, or features → matching directories or entry points

Then search for prior art:

```bash
gh issue list --state all --search "<keywords from seed>" --json number,title,state,url --limit 10
```

If a candidate looks like a near-duplicate (similar title or significant body overlap), present it and ask via `AskUserQuestion`:

> Looks similar to [#N](url). Continue creating, comment on the existing one instead, or cancel?

Only proceed past this point on explicit user choice. Never silently dedupe.

### 4. Draft the issue body

Structure every drafted body the same way:

```markdown
## Summary
One to two sentences stating the problem or change.

## Context
Why this matters now — the motivation, user impact, or constraint that prompted it.

## Acceptance criteria
- [ ] Testable bullet one
- [ ] Testable bullet two

## Affected area
- `path/to/file.ext:42` — what this file does relative to the issue
- `path/to/other.ext` — secondary reference

## Related
- [#N](url) — related issue or PR title (omit section if none)
```

Title rules:

- Imperative mood ("Fix dashboard timeout on large orgs", not "Dashboard is timing out").
- ≤ 70 characters (mirrors `pr-description` convention).
- No issue numbers or `[scope]` prefixes — labels carry that signal.

### 5. Preview + confirm

Show the user a single rendered preview:

```
Title:   <title>
Type:    <Bug | Feature | Chore | Docs | Refactor | Question>
Labels:  <comma-separated>

<body>
```

Then ask via `AskUserQuestion`:

> Create this issue, revise, or cancel?

Options: **Create as shown** / **Revise** (loop back to step 4 with the user's edits) / **Cancel**.

Never call `gh issue create` without an explicit "Create as shown" choice.

### 6. Create

On confirmation, create the issue with a HEREDOC pattern so multi-line formatting is preserved:

```bash
gh issue create \
  --title "<title>" \
  --label "<label1>,<label2>" \
  --body "$(cat <<'EOF'
<body>
EOF
)"
```

After creation, set the issue type via GitHub's GraphQL API (same pattern `/improve-issues` uses for the built-in issue type field — not a label). If the repo has no issue types configured, skip silently.

Report the new issue URL back to the user.

### 7. Batch loop

If invoked with `--batch`, after each successful create ask via `AskUserQuestion`:

> Draft another issue, or finish?

On "Draft another", return to step 1 with no seed (fully interactive). On "Finish", print a one-line summary of every issue created in the session:

```
Created 3 issues:
- [#412](url) — <title>
- [#413](url) — <title>
- [#414](url) — <title>
```

## Rules

- **One `gh` call per Bash invocation.** The repo's never-chain-git rule extends to `gh`: separate `gh label list`, `gh issue list`, and `gh issue create` into discrete calls so the allowlist matches and intermediate output is inspectable.
- **Never create silently.** Steps 3 (duplicate prompt) and 5 (preview) both require explicit user choice. Silence is never approval.
- **Never invent acceptance criteria.** If the user cannot articulate them, draft the issue with a placeholder section and a `needs-triage` label suggestion.
- **Title in imperative mood, ≤ 70 chars.** Reject (loop back to step 4) any title that fails this.
- **Working tree is untouched.** This skill never edits files, commits, or pushes. Only GitHub state changes, and only after confirmation.
- **Label suggestions come from `gh label list`, not invention.** If no suitable label exists, do not propose one — flag it instead and let the user add it manually.
- **Duplicate detection is advisory, not blocking.** Always show candidates; never auto-skip creating an issue based on similarity alone.
