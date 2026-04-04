---
name: pr-description
description: Generate a structured PR description from the current branch's diff and commit history.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# /pr-description

Generate a structured PR description from the current branch's diff and commit history. Outputs markdown for `gh pr create --body` or pasting into a PR description field.

## Steps

### 1. Gather context

Run git commands (read-only):

```bash
git diff origin/main...HEAD --stat
git log origin/main..HEAD --oneline
git diff origin/main...HEAD --name-only
```

If `origin/main` does not exist, try `origin/master`. If neither exists, report the error and stop.

### 2. Analyze changes

Read changed files to understand:

- What was added, modified, or removed
- Which areas are affected (auto-detect from directory structure and file paths)
- Whether there are breaking changes
- Whether there are new capabilities or behavioral changes

### 3. Auto-detect change areas

Group the changed files by logical area. Derive area names from the directory structure — do not use hardcoded categories. Examples:

- Files in `src/auth/` and `src/middleware/` -> "Authentication & Middleware"
- Files in `terraform/` -> "Terraform"
- Files in `tests/` and `e2e/` -> "Tests"
- Files in `docs/` -> "Documentation"
- Files in `scripts/` or `.github/` -> "Tooling & CI"
- Files in the project root -> "Configuration"

Use the actual directory names from the project. If all changes are in a single area, use a flat list instead of area sub-sections.

### 4. Generate PR description

Output this markdown structure:

```markdown
## Summary

- Bullet points of what changed (be specific, not vague)

## Motivation

Why this change was made. Link to the problem being solved. Reference the issue number if the branch name contains one.

## Changes by area

### <Area 1 — derived from directory structure>
- <specific change>
- <specific change>

### <Area 2>
- <specific change>

> Skip empty areas. Only include areas with actual changes.
> If all changes are in one area, skip sub-headings and use a flat list.

## Testing

- What was validated and how
- New test files added
- Manual verification steps

## Breaking changes

> Only include this section if there are breaking changes.

- What breaks and what consumers/users need to do
```

### 5. Output

Print the generated markdown. Also suggest a PR title in conventional commit style: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`.

Format:

```
**Suggested title**: `<conventional-commit-style title>`

---

<PR body markdown>
```

## Rules

- Be specific: "Add rate limiting to authentication endpoints" not "Update auth"
- Be concise: each bullet one line
- Skip empty sections (except Summary and Motivation — always required)
- Use conventional commit style for suggested PR title
- Only use Bash for git commands — read-only, never modify files
- Area groupings come from actual file paths, never from hardcoded templates
- If the branch name contains an issue number (e.g., `fix/42-auth-bug`), reference it in Motivation as "Closes #42" or "Fixes #42"
