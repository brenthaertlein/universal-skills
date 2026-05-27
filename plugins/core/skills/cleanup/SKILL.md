---
name: cleanup
description: Remove worktrees and local branches whose pull request has been merged or closed.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash
---

# Cleanup -- Remove Worktrees & Branches for Finished Work

Clean up local worktrees and branches whose pull request has been **merged or
closed** on GitHub.

This is a user-invoked, full-repo sweep. It is safe to run from inside a
worktree — every removal runs from the main working tree.

## Usage

```
/cleanup
```

No arguments. The skill determines what is safe to remove automatically.

## Why merged-PR detection (not the commit graph)

A branch with zero commits ahead of `origin/main` is **not** necessarily
finished work. A freshly created worktree branched from `origin/main` is
graph-identical to a fully merged branch — both have nothing ahead of
`origin/main`. Judging "done" by the commit graph (`git branch --merged`)
therefore destroys brand-new, in-progress worktrees that parallel sessions are
actively using.

Instead, a worktree counts as finished only when GitHub reports a **merged or
closed PR** for its branch. No PR → not finished → keep it.

## What It Does

1. **Fetch** `origin/main` so PR/branch state is current
2. **Resolve** the main working tree (removals run from there)
3. **Scan** every worktree except the main tree:
   - No merged or closed PR for the branch → keep it, report why
   - Uncommitted or untracked changes present → keep it, report why
   - Otherwise: remove the worktree and safe-delete the local branch
4. **Prune** stale worktree references (`git worktree prune`)
5. **Report** a summary of what was removed and what was kept (and why)

## Execution

```bash
# 1. Fetch latest state from origin
git fetch origin main

# 2. Resolve the main working tree — the first entry of `git worktree list`.
#    Running removals from here makes removing the *current* worktree safe.
MAIN_TREE=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

# 3. Iterate every worktree except the main tree
git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r WT; do
  [ "$WT" = "$MAIN_TREE" ] && continue

  BRANCH=$(git -C "$WT" rev-parse --abbrev-ref HEAD)

  # Finished work only — a merged or closed PR must exist for this branch.
  MERGED=$(gh pr list --head "$BRANCH" --state merged --json number --jq 'length')
  CLOSED=$(gh pr list --head "$BRANCH" --state closed --json number --jq 'length')
  if [ "${MERGED:-0}" -eq 0 ] && [ "${CLOSED:-0}" -eq 0 ]; then
    echo "KEEP    $WT ($BRANCH) -- no merged or closed PR"
    continue
  fi

  # Never discard uncommitted or untracked work.
  if [ -n "$(git -C "$WT" status --porcelain)" ]; then
    echo "KEEP    $WT ($BRANCH) -- uncommitted or untracked changes"
    continue
  fi

  # Remove from the main tree so removing the current worktree is safe.
  if git -C "$MAIN_TREE" worktree remove "$WT"; then
    git -C "$MAIN_TREE" branch -d "$BRANCH" 2>/dev/null \
      && echo "REMOVED $WT ($BRANCH) -- worktree + branch" \
      || echo "REMOVED $WT ($BRANCH) -- worktree only (branch not safe to delete)"
  else
    echo "KEEP    $WT ($BRANCH) -- worktree remove failed"
  fi
done

# 4. Prune any stale worktree references
git -C "$MAIN_TREE" worktree prune
```

Report the output to the user: which worktrees were removed, which were kept
(and why), and the final state.

## Safety Rules

- **Merged/closed-PR detection only** -- never judges "done" by the commit
  graph; a branch with no PR is never removed, so fresh worktrees survive
- **Never removes worktrees with uncommitted or untracked changes**
- **Removes from the main working tree** -- safe even when run from inside the
  worktree being removed
- **Never force-deletes branches** -- uses `git branch -d` (safe delete), never
  `-D`; a branch that is not safe to delete is reported and left in place
- **Never deletes remote branches** -- local cleanup only
- **Fetches before checking** -- prevents false positives from stale local refs
- **Reports everything** -- the user sees exactly what was removed and what was
  kept (and why)
