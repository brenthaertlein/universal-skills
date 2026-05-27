---
name: ship-it
description: Finalize work — commit via /commit, push, and create PRs on feature branches.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob, Edit, Write, Agent, AskUserQuestion
---

# Ship It

Finalize the current branch: commit with preflight, push, and create/update a PR on feature branches.

## Steps

### 1. Commit (via /commit)

Run `/commit`'s Steps 1-5:

1. **Branch check** — note the current branch and apply branch policy from CLAUDE.md. Also check if this branch has a merged/closed PR:
   ```bash
   gh pr view --json number,state,url 2>/dev/null
   ```
   If the PR state is `MERGED` or `CLOSED`, warn the user and ask with `AskUserQuestion`:
   - **Create a new branch** (Recommended) — branch from `origin/main` with a new name, re-apply uncommitted changes
   - **Continue on this branch** — push new commits and create a fresh PR (the old PR will be referenced)
   - **Cancel** — stop

2. **Review changes** — show diff, ask "stage all or pick?"

3. **Preflight** — run project-defined checks from CLAUDE.md (see `/commit` step 3)

4. **Commit** — write commit message, append `Co-Authored-By`, use HEREDOC

5. **Summary** — report preflight results

If any of `/commit`'s steps would stop (branch policy violation, preflight failure, nothing to commit), stop here too.

If the working copy is clean but there ARE commits ahead of main, skip to step 2 — the work is already committed.

### 2. Push

#### 2a. CI status gate (follow-up pushes only)

If the current branch already has an open PR (detected via `gh pr view --json number,state` returning `state: OPEN`), gate on CI status before pushing:

```bash
gh pr checks --required
```

Block if any required check is in a non-passing state. Only `SUCCESS` and `NEUTRAL` count as passing; `FAILURE`, `IN_PROGRESS`, `PENDING`, and `QUEUED` all block. Report which checks are blocking and stop — let the user decide whether to wait, fix, or override.

Skip this gate on the first push to a branch (no PR exists yet → no checks to gate on).

**Configurable via CLAUDE.md key `ship-it.ci-gate`:**

- `enabled` (default) — gate as described above.
- `disabled` — skip the gate entirely.
- `{ states: [<list of states to block on>] }` — fine-grained control. Example: `{ states: ["FAILURE"] }` allows stacked pushes while CI is running.

#### 2b. Push

```bash
git push -u origin HEAD
```

If the push fails (e.g., rejected, no remote), report the error and stop. Never chain push onto commit with `&&` — commit and push are separate commands so the user can inspect the post-commit state before pushing.

### 3. Create or Update PR (feature branches only)

**If on `main` or `master`:** Skip this step. No PR needed for direct-to-main workflows.

**If on a feature branch:**

Check for existing PR:
```bash
gh pr view --json number,title,url,state 2>/dev/null
```

#### If no PR exists, or existing PR is MERGED/CLOSED:

If a merged/closed PR was found, note it for context in the new PR body (e.g., "Continues work from #278").

1. Generate the PR body via `/pr-description`. That skill already analyzes the branch's diff and commit history, auto-detects change areas from directory structure, and emits the canonical Summary / Motivation / Changes-by-area / Testing / Breaking-changes structure. Do not re-implement that logic here.

2. Pipe the generated body into `gh pr create` via a HEREDOC:

```bash
PR_BODY=$(/pr-description)  # or capture the skill's output by whatever mechanism the harness uses

gh pr create --title "<conventional-commit-style title>" --body "$(cat <<EOF
${PR_BODY}

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

`/pr-description` is the single source of truth for the PR body format — `/ship-it` must never inline its own template.

#### If an OPEN PR already exists:

Check for new commits since last push:
```bash
git log origin/<branch>..HEAD --oneline
```

If there are new commits, add an update comment:
```bash
gh pr comment <number> --body "$(cat <<'EOF'
## Update

<2-3 bullet points summarizing what changed in this push>

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 4. Summary & Follow-Up

Present:

```
## Ship-it Summary

### Preflight
- <Check category>: PASS | FIXED | SKIPPED | N/A
- ...

### Push
- Branch: <branch>
- Pushed: <short-hash range>
- PR: <pr-url> (feature branches only)
```

Then ask: **"PR is up. Anything else before moving on?"**

Suggest 2-3 concrete follow-ups tailored to the actual changes. Read the diff to make relevant suggestions — do not use generic boilerplate. Examples of the kind of follow-ups to suggest:

- "Run the project's full test suite to validate end-to-end"
- "Deploy to a staging environment to verify the changes"
- "Review the changes in the PR diff before requesting review"
- "Address the N warnings from preflight (see above)"

Tailor suggestions to what actually changed. If files in a testing directory changed, suggest verifying test coverage. If configuration changed, suggest validating in a real environment. If documentation changed, suggest reviewing for accuracy.

## Supporting Skills Integration

If `superpowers:requesting-code-review` is available, dispatch a code-reviewer subagent after PR creation. This provides an automated first-pass review before human reviewers see the PR.

**`superpowers:finishing-a-development-branch`** — If available and you are completing a branch produced by `subagent-driven-development` (worktree-based, full implementation pipeline), use `finishing-a-development-branch` instead of `/ship-it`. It handles worktree cleanup and offers merge-locally and discard options that `/ship-it` does not provide. For standalone branches not created by the superpowers pipeline, `/ship-it` is the right tool.

## Rules

- **Branch policy comes from CLAUDE.md** — respect whatever the project defines
- Never prompt the user for permission to edit, push, or commit — those are pre-authorized by this skill
- The ONLY user prompts are: step 1's staging question (via `/commit`), the merged/closed PR question, and the follow-up in step 4
- If any blocking check fails, stop and report clearly — do not push broken code
- **Never chain `git commit && git push` on one line.** Commit and push are separate commands so the user can inspect the post-commit state before pushing. `/ship-it` invokes them sequentially as distinct steps — that is the canonical pattern.
- **CI gate before follow-up pushes.** When pushing to a branch that already has an open PR, gate on `gh pr checks --required` (see step 2a). Configurable via CLAUDE.md `ship-it.ci-gate`.
- Commit messages must end with `Co-Authored-By: <co-author line from CLAUDE.md, or default to current model>`
- Use HEREDOC for all commit messages and PR bodies to preserve formatting
- **PR body is generated by `/pr-description`** — never inline a template in `/ship-it` itself. Keeps both skills from drifting.
- If `gh` CLI is not available or not authenticated, push succeeds but PR creation is skipped with a clear message
