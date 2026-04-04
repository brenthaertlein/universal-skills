---
name: improve-issues
description: Enrich open GitHub issues with descriptions, labels, types, code references, and cross-links.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, AskUserQuestion
---

# Improve Issues

Enrich GitHub issues with actionable context: structured descriptions, code references, labels, issue types, and cross-links.

## How to use

When invoked with `/improve-issues`, process all open issues from the last 48 hours. Accepts optional arguments:

- `/improve-issues 182` -- process a single issue
- `/improve-issues --author username` -- filter by author
- `/improve-issues --label "priority: high"` -- filter by label
- `/improve-issues --apply` -- skip confirmation and apply immediately

## Workflow

### 1. Fetch issues

```bash
# Default: open issues created in the last 48 hours
gh issue list --state open --json number,title,body,labels,createdAt --limit 50 \
  --search "created:>$(date -u -v-48H '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d '48 hours ago' '+%Y-%m-%dT%H:%M:%S')"
```

Filter by args if provided. Without args, scope to issues created in the last 48 hours.

### 2. Classify each issue

For each issue, determine:

- **Type** (via GitHub's built-in issue type field, not labels): Bug (unexpected behavior), Feature (new capability), Task (chore/upgrade/refactor)
- **Labels** -- apply labels that match the project's taxonomy. Check CLAUDE.md for the project's label scheme. If no taxonomy is defined, suggest labels based on the files and areas the issue touches. Common categories include:
  - **Priority** labels (e.g. `priority: high`, `priority: low`)
  - **Area** labels (e.g. `area: frontend`, `area: api`, `area: database`) -- infer from file paths and component names mentioned in the issue
  - **Driver** labels (e.g. `driver: engineering`, `driver: product`)
  - **Accessibility** labels (e.g. `good first issue`, `help wanted`) -- for self-contained issues with clear acceptance criteria
  - **Workflow** labels (e.g. `needs triage`) -- when classification is uncertain
- **Description quality**: empty (0 chars), minimal (under 200 chars or no code refs), rich (structured with context)

### 3. Gather context per issue

For each issue:

1. Search the codebase for files/functions mentioned in the title or body using Grep and Glob
2. Find related open/closed issues and PRs via `gh issue list`/`gh pr list` with keyword search
3. Read relevant source files to provide specific line references and understand the code paths involved

### 4. Report (default mode)

Output a summary table of proposed changes:

```
| # | Title | Type | Labels | Missing Labels | Action | Related |
|---|-------|------|--------|---------------|--------|---------|
| 182 | Fix mobile layout | Bug | priority: high, area: frontend | -- | Update body | #174 |
| 184 | Upgrade tooling | Task | -- | priority, area | Add labels | -- |
```

Ask for user confirmation before applying changes.

### 5. Check for existing automated comments

Before adding a comment, check whether a previous `/improve-issues` run already left one. Automated comments use a canonical format -- the body **must** begin with this exact header:

```markdown
## Additional Context
<!-- improve-issues automated comment; do not edit this line -->
```

To detect existing automated comments:

```bash
gh api repos/{owner}/{repo}/issues/{number}/comments \
  --jq '[.[] | select(.body | contains("<!-- improve-issues automated comment"))]'
```

- If an automated comment already exists and the new content is a **superset** (more code refs, more related issues), **edit the existing comment** via `gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id}` rather than adding a second one.
- If the existing comment covers different ground, consolidate both into one updated comment.
- **Never leave duplicate automated comments on the same issue.** One automated comment per issue, max.

### 6. Apply changes

After confirmation (or if `--apply` was passed):

**For empty/minimal issues** -- update the body with a structured description:
```markdown
## Summary
Brief description of the issue.

## Steps to Reproduce (bugs only)
1. Step one
2. Step two

## Current Behavior
What happens now.

## Expected Behavior
What should happen.

## Relevant Code
- `src/path/to/file:42` -- description of relevant code

## Suggested Fix
Brief suggestion for how to fix.

## Related Issues
- #123 -- related issue title
```

**For rich issues** -- add a single follow-up comment with:
- Additional code references found via codebase search
- Related issues/PRs not already mentioned
- Suggested implementation approach or complexity estimate

**For all issues:**
- Set issue type via GitHub's GraphQL API:
  ```bash
  gh api graphql -f query='
    mutation($id: ID!, $typeId: ID!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $projectId, itemId: $id,
        fieldId: $fieldId, value: {singleSelectOptionId: $typeId}
      }) { projectV2Item { id } }
    }
  ' -f id=ITEM_ID -f typeId=TYPE_ID
  ```
- Add labels:
  ```bash
  gh issue edit {number} --add-label "label1,label2"
  ```
- Set sub-issue relationships where one issue gates another:
  ```bash
  gh api graphql -f query='
    mutation($parentId: ID!, $childId: ID!) {
      addSubIssue(input: {issueId: $parentId, subIssueId: $childId}) {
        issue { id }
      }
    }
  '
  ```

### 7. Output summary

Always end with a matrix showing every issue touched:

```
## Issue Enrichment Summary

| # | Title | Type | Labels Added | Missing Labels | Title Changed | Body Updated | Comment | Relationships |
|---|-------|------|-------------|---------------|---------------|-------------|---------|---------------|
| 182 | Fix mobile... | Bug | priority: high, area: frontend | -- | No | Yes (was empty) | No | -- |
| 184 | Upgrade... | Task | driver: engineering | priority, area | No | No | 1 added | gates #183 |
```

Column definitions:
- **Type**: Bug, Feature, or Task -- set via GitHub's built-in issue type field
- **Labels Added**: labels added in this run (not pre-existing)
- **Missing Labels**: required labels still missing after this run -- flags issues needing human input
- **Title Changed**: Yes/No -- only when the original title was unclear or incoherent
- **Body Updated**: Yes (was empty), Yes (prepended to existing), or No
- **Comment**: "1 added", "1 updated" (edited existing), or "No"
- **Relationships**: sub-issue links set (e.g., "sub of #172")

## Safety rules

- **Never overwrite** a body that has more than 2 sentences, code references, or links -- add a comment instead
- **Never overwrite** comments authored by an automated tool with sufficient detail
- **Preserve existing content** -- prepend/append if updating a body that has some content
- **One automated comment per issue** -- edit existing automated comments rather than adding duplicates
- **Always confirm** before applying (unless `--apply` is passed)
- **Never remove user-applied labels** -- only add missing ones; you may remove workflow labels like `needs triage` once required labels and an issue type have been set
- **Label taxonomy is project-specific** -- check CLAUDE.md for the project's label conventions before applying labels. If no taxonomy is defined, suggest sensible labels based on changed files and issue content, but flag them for user review.
