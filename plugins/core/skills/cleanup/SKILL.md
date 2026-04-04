---
name: cleanup
description: Remove worktrees and local branches for merged work.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash
---

# Cleanup -- Remove Merged Worktrees & Branches

Clean up local worktrees and branches that have been fully merged into `origin/main`.

## Usage

```
/cleanup
```

No arguments. The skill determines what is safe to remove automatically.

## What It Does

1. **Fetch** `origin/main` to ensure merge detection is accurate
2. **Scan** each worktree in `.worktrees/`:
   - Check if the branch's commits are all in `origin/main`
   - If merged: remove the worktree and delete the local branch (safe delete only)
   - If NOT merged: keep it and report why
3. **Prune** stale worktree references (`git worktree prune`)
4. **Report** a summary of what was cleaned and what was kept

## Execution

```bash
# Fetch latest state from origin
git fetch origin main

# List all worktrees
git worktree list

# For each worktree in .worktrees/:
# Check if branch is fully merged into origin/main
git branch --merged origin/main | grep <branch-name>

# If merged, remove the worktree and branch
git worktree remove .worktrees/<worktree-dir>
git branch -d <branch-name>

# Prune any stale worktree references
git worktree prune
```

Report the output to the user: which worktrees were removed, which were kept (and why), and the final state.

## Safety Rules

- **Never force-deletes branches** -- uses `git branch -d` (safe delete), never `-D`
- **Never deletes remote branches** -- local cleanup only
- **Never removes unmerged work** -- if a branch has commits not in `origin/main`, it stays
- **Fetches before checking** -- prevents false positives from stale local refs
- **Reports everything** -- the user sees exactly what was cleaned and what was kept
