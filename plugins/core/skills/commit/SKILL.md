---
name: commit
description: Run project-defined preflight checks and commit work. Does not push or create PRs.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob, Edit, Write, Agent, AskUserQuestion
---

# Commit

Run project-defined preflight checks and commit changes. Does not push or create PRs — use `/ship-it` for the full pipeline.

## Arguments

- **No args** (`/commit`): Run all checks, commit.
- **`--fix`** (`/commit --fix`): Auto-fix what is safe to auto-fix (formatting, lint, type errors) before committing. Does not auto-fix test failures — those require human judgment.

## Steps

### 1. Branch Check

```bash
git branch --show-current
```

Note the current branch. Check the project's branch policy:

- **Read CLAUDE.md** for branch policy. Look for instructions about committing to `main` or `master` (e.g., "never commit to main", "main commits allowed", branch protection rules).
- **If CLAUDE.md blocks main**: Stop immediately. Tell the user: "You're on `main`. Create a feature branch first (`git checkout -b <branch-name>`) or run `/start-work` to begin from an issue."
- **If CLAUDE.md allows main**: Proceed. Note it in output.
- **If CLAUDE.md is silent**: Warn but allow. "You're on `main`. CLAUDE.md has no branch policy — proceeding, but consider using a feature branch."

### 2. Review Changes

```bash
git status
git diff --stat
```

- **If there are unstaged or untracked changes:** Show a summary of what changed (files modified, added, deleted). Ask the user ONE question: "Stage all changes, or should I pick the relevant ones?" Then stage accordingly.
  - If **all**: stage everything.
  - If **pick**: select files aligned with the branch's purpose, explain what was excluded and why.
- **If working copy is clean AND no commits ahead of main:** Report "Nothing to commit." and stop.
- **If working copy is clean BUT commits exist ahead of main:** Report "Working copy is clean — nothing new to commit. Use `/ship-it` to push existing commits." and stop.

### 3. Preflight Checks

Run project-defined checks scoped to staged changes. The specific checks come from CLAUDE.md or project configuration — this skill defines the workflow, not the tools.

#### 3a. Scope detection

```bash
git diff --cached --name-only
```

Categorize staged files by directory and extension. Only run checks relevant to the changed file types.

#### 3b. Run project checks

Read CLAUDE.md for the project's defined check commands. Common categories:

- **Linting / formatting** — run the project's lint and format commands
- **Type checking** — run the project's type checker if applicable
- **Unit tests** — run the project's test suite
- **Integration / E2E tests** — run if the project defines them and staged changes affect testable code
- **Validation** — run any project-specific validation (schema validation, config checks, etc.)

For each category:
1. Check if CLAUDE.md defines a command for it
2. If yes, run it against the appropriate scope
3. If no command is defined, skip gracefully — do not guess or invent commands

**If `--fix` was passed:** For checks that support auto-fix (linting, formatting, type errors), run the fix variant first, then re-run the check to verify. Never auto-fix test failures.

**If any check that ran (not skipped) fails:** Stop and report the failures. Do not commit broken code. Missing tools or undefined checks are skipped, not failures.

#### 3c. Domain plugin override

Domain plugins may override or extend this phase with project-specific checks. If a domain plugin's `/commit` skill is active, its preflight checks take precedence over the generic flow above.

### 4. Commit

After preflight passes:

1. Analyze the staged diff with `git diff --cached`
2. Check recent commit style: `git log --oneline -10`
3. Write a thorough commit message that describes the what and why
4. Always use HEREDOC format:

```bash
git commit -m "$(cat <<'EOF'
<commit message>

Co-Authored-By: <co-author line from CLAUDE.md, or default to current model>
EOF
)"
```

If the commit fails (e.g., a pre-commit hook rejects it), report the hook output to the user and stop. Do not retry automatically.

### 5. Summary

After successful commit, report:

```
## Commit Summary

- Branch: <branch-name>
- Commit: <short-hash> <first line of message>
- <Check category>: PASS | FIXED | SKIPPED | N/A
- <Check category>: PASS | FIXED | SKIPPED | N/A
- ...

Next: Run /ship-it to push.
```

List each check category that was evaluated. PASS means it passed, FIXED means `--fix` resolved issues, SKIPPED means the check was not relevant to staged files, N/A means no command is defined for that category.

## Superpowers Integration

The `superpowers:verification-before-completion` skill complements this skill's automated checks. Where `/commit` runs concrete project-defined commands, verification-before-completion ensures that success claims are backed by evidence. They layer naturally — verification-before-completion is the discipline, `/commit` is the execution.

## Rules

- **Branch policy comes from CLAUDE.md** — this skill does not hardcode a policy. Default: warn but allow.
- **Never push** — this skill only commits locally. Pushing is a separate action.
- **Never amend commits** — always create new commits. If a hook fails, fix the issue, re-stage, and create a new commit.
- **Co-Authored-By** — every commit message must end with the co-author line.
- **HEREDOC** — always use HEREDOC format for commit messages to preserve formatting.
- **No broken commits** — if any preflight check fails, stop. Do not commit.
- **Skip missing tools gracefully** — undefined checks and missing tools are SKIPPED, not failures. Only actual validation failures block the commit.
- **`--fix` is conservative** — auto-fix formatting, linting, and type errors. Never auto-fix test failures. Never auto-fix anything that changes runtime behavior.
