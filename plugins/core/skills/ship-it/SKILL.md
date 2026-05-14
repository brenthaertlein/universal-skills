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

```bash
git push -u origin HEAD
```

If the push fails (e.g., rejected, no remote), report the error and stop.

### 3. Create or Update PR (feature branches only)

**If on `main` or `master`:** Skip this step. No PR needed for direct-to-main workflows.

**If on a feature branch:**

Check for existing PR:
```bash
gh pr view --json number,title,url,state 2>/dev/null
```

#### If no PR exists, or existing PR is MERGED/CLOSED:

If a merged/closed PR was found, note it for context in the new PR body (e.g., "Continues work from #278").

1. Analyze all commits on the branch:
   ```bash
   git log origin/main..HEAD
   git diff origin/main...HEAD
   ```

2. Read changed files to understand scope.

3. Create the PR with structured description:

```bash
gh pr create --title "<conventional-commit-style title>" --body "$(cat <<'EOF'
## Summary
<specific bullet points describing what changed>

## Motivation
<why this change was made — link to the problem being solved>

## Changes by area
<group changes by directory/area — auto-detect groupings from changed file paths>
<skip empty areas — only list areas with actual changes>

### <Area 1 — derived from directory structure>
- <changes>

### <Area 2>
- <changes>

## Testing
<what was tested, how to verify, new test files if any>

## Breaking changes
> Only include if there are breaking changes.
- <what breaks and what needs to happen>

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Auto-detect areas:** Group changes by top-level directory or logical area derived from the changed file paths. Do not use hardcoded section headers — let the actual changes dictate the groupings. Examples: if files changed in `src/auth/` and `src/api/`, use "Authentication" and "API" as area headers. If files changed in `terraform/` and `ansible/`, use those as headers.

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
- Commit messages must end with `Co-Authored-By: <co-author line from CLAUDE.md, or default to current model>`
- Use HEREDOC for all commit messages and PR bodies to preserve formatting
- PR section headers are auto-detected from changed file paths, not hardcoded
- If `gh` CLI is not available or not authenticated, push succeeds but PR creation is skipped with a clear message
