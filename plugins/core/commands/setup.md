---
name: setup
description: Configure recommended permissions for the core plugin
---

Configure recommended permissions for the core plugin by merging them into `.claude/settings.json`.

## Recommended Permissions

The following permissions should be added to `.claude/settings.json` under `permissions.allow`:

```json
[
  "Bash(git log*)",
  "Bash(git status*)",
  "Bash(git diff*)",
  "Bash(git show*)",
  "Bash(git fetch*)",
  "Bash(git branch --show-current*)",
  "Bash(git branch -a*)",
  "Bash(git branch --list*)",
  "Bash(git stash list*)",
  "Bash(git stash show*)",
  "Bash(git worktree list*)",
  "Bash(gh pr view*)",
  "Bash(gh pr list*)",
  "Bash(gh pr checks*)",
  "Bash(gh pr diff*)",
  "Bash(gh pr status*)",
  "Bash(gh run view*)",
  "Bash(gh run list*)",
  "Bash(gh issue list*)",
  "Bash(gh issue view*)",
  "Bash(gh repo view*)",
  "Bash(gh api repos/*/pulls/*/reviews*)",
  "Bash(gh search issues*)",
  "Bash(gh search prs*)",
  "Write(.claude/plans/*)",
  "Edit(.claude/plans/*)"
]
```

> **Note:** Only read-only operations are auto-allowed. Mutating operations (commit, push, merge, branch create, PR create, issue edit) will always prompt for approval.

## Instructions

When this command is invoked, follow these steps exactly:

1. **Read** `.claude/settings.json` if it exists. If it does not exist, start with an empty object `{}`.
2. **Parse** the JSON. Extract the existing `permissions.allow` array. If `permissions` or `permissions.allow` does not exist, treat it as an empty array.
3. **Merge** the recommended permissions listed above into the existing `permissions.allow` array. Do NOT add duplicates -- skip any permission that already exists in the array.
4. **Write** the updated JSON back to `.claude/settings.json`, preserving all other existing keys and values in the file. Use 2-space indentation for readability.
5. **Report** the result to the user: "Added N permissions for core plugin. Existing permissions preserved." where N is the number of new permissions that were actually added (not already present). If all permissions were already present, say "All core plugin permissions already configured. No changes needed."
