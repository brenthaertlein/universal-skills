---
name: pr-fix
description: Fetch PR review comments, classify by severity and confidence, and fix the selected subset.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# PR Fix -- Review Comment Triage & Fix

Fetch review comments from the current branch's PR, classify each issue, present a prioritized matrix, and fix the selected subset.

## How to use

Invoke with `/pr-fix`. Must be on a branch with an open PR. No arguments needed.

## Steps

### 1. Fetch PR comments

Use the GitHub CLI to gather all review feedback:

```bash
# Get PR number and repo
gh pr view --json number,headRefName,headRepository

# PR-level comments (issue comments)
gh api --paginate repos/{owner}/{repo}/issues/{number}/comments

# Code review comments (inline)
gh api --paginate repos/{owner}/{repo}/pulls/{number}/comments

# PR review bodies (review-level feedback)
gh api --paginate repos/{owner}/{repo}/pulls/{number}/reviews
```

Parse the JSON responses with `jq`. For each review comment, extract: `id` (needed for replies), `body`, `path`, `line` (or `original_line`), `diff_hunk`, and `user.login`. Retain the comment `id` throughout classification so it can be used in step 7.

### 2. Filter out noise

Skip comments that are NOT substantive review feedback:

- Coverage report bots (e.g. `github-actions[bot]` posting coverage tables)
- CI status comments
- Auto-generated PR descriptions
- Comments that are purely informational with no actionable feedback
- Already-resolved review threads (use GraphQL `reviewThreads` query from step 7 to check `isResolved`)

Keep comments from: human reviewers, automated code review sections (look for headings like "Blocker", "Warning", "Suggestion"), and code review bot comments with substantive feedback.

When a single comment contains multiple distinct issues (e.g. a review with separate sections), split them into individual issues for the matrix.

### 3. Classify each issue on four axes

For each issue, assign:

| Axis | Values | Definition |
|------|--------|------------|
| **Severity** | Blocker / Warning / Suggestion | Impact if left unfixed. Blocker = bug, broken behavior, or data loss. Warning = correctness risk or code smell. Suggestion = improvement, style, or nice-to-have. |
| **Confidence** | Unambiguous / Debatable | Whether the fix is objectively correct (Unambiguous) or a matter of opinion, tradeoff, or requires product/design input (Debatable). |
| **Effort** | Quick / Involved | Quick = mechanical change, less than 5 min. Involved = requires thought, testing, design decisions, or touches multiple files. |
| **Scope** | In / Out / Ambiguous | Whether the issue is in scope for the current branch's work. See **Scope classification** below. "Out" covers both out-of-scope surface and out-of-scope subject. |

Derive a **Recommendation** column:
- **Fix now**: Unambiguous, in-scope issues of any severity
- **Discuss**: Debatable issues at Warning or Blocker severity
- **Optional**: Debatable suggestions or low-priority items
- **Defer**: Out-of-scope issues regardless of severity — track separately

### 3a. Scope classification

If `core:scope-statement-check` is available and a scope contract exists for this branch (`.claude/scope/<branch>.md`), invoke `scope-statement-check classify` on the filtered findings. This attaches a **Scope** axis to each finding:

- **in-scope** — path and subject match the contract's In Scope bullets
- **out-of-scope** — path or subject is explicitly excluded by the contract
- **ambiguous** — neither clearly in nor clearly out

Out-of-scope findings default to **Defer** in the Recommendation column and receive a generated deferral rationale from scope-statement-check that pre-fills the reply template in step 7.

If the skill is not available, or no contract exists for this branch, classify scope inline: read the contract at `.claude/scope/<branch>.md` if present, apply the same in/out/ambiguous logic, and default out-of-scope findings to Defer. If no contract exists at all, skip scope classification and proceed. Suggest the user run `/scope-statement-check extract` for future branches.

Out-of-scope issues default to **Defer** regardless of severity. The user can override case-by-case in step 5. This is the single largest source of review-cycle waste — bots and reviewers consistently flag legitimately out-of-scope work, and a contract-based default removes the keystroke cost of explaining each one.

### 4. Present the matrix

Output a markdown table sorted by recommendation priority (Fix now > Discuss > Optional), then by severity (Blocker > Warning > Suggestion):

```markdown
| # | Issue | File | Scope | Severity | Confidence | Effort | Recommendation |
|---|-------|------|-------|----------|------------|--------|----------------|
| 1 | Description | path#line | In | Blocker | Unambiguous | Quick | Fix now |
| 2 | Description | path#line | Out | Warning | Unambiguous | Involved | Defer |
| ...
```

When scope classification was skipped (no contract), omit the Scope column.

Below the table, provide a brief summary:
- How many issues total
- How many per recommendation category
- Any issues where multiple reviewers flagged the same thing (adds weight)

### 5. Prompt the user

If all issues are already fixed (e.g. addressed in a prior commit), skip straight to step 7 -- do not prompt for a fix category.

If every remaining issue is classified as **Fix now + Quick**, skip the prompt and fix them all -- the selection adds no value when there is only one sensible answer.

Otherwise, use `AskUserQuestion` with these options:

- **All** -- Fix every reported issue
- **Blocker + Unambiguous** -- Only issues that are both Blocker severity and Unambiguous confidence
- **Unambiguous only** -- All issues where the fix is objectively correct, regardless of severity
- **Quick wins** -- Unambiguous + Quick effort (low-hanging fruit)

### 6. Apply fixes

After the user selects a category:

1. Read each referenced file before making changes
2. Apply the fixes for the selected issues
3. Run the project's lint/format tooling to clean up any issues introduced by fixes (check CLAUDE.md for project-specific commands)
4. Run the project's test suite to verify nothing is broken (check CLAUDE.md for project-specific commands)
5. Report which issues were fixed and which remain

Do NOT commit -- the user will decide when to commit.

If a "Debatable" issue is included in the selection (via "All"), mention the tradeoff to the user before fixing and let them confirm.

### 7. Update PR comments

After fixes are applied, update the PR to reflect what was addressed.

#### Resolve fixed comment threads (automatic)

Use GraphQL to fetch review thread IDs and resolve threads whose issues were fixed. This is safe to do automatically -- resolving is reversible and self-evident from the diff.

```bash
# Fetch review threads with their comment bodies and thread IDs
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 10) {
              nodes { body databaseId author { login } }
            }
          }
        }
      }
    }
  }
' -f owner=OWNER -f repo=REPO -F pr=NUMBER

# Resolve a thread
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }
' -f threadId=THREAD_NODE_ID
```

Match each fixed issue back to its review thread by comparing the comment body/path/line from the original fetch. Resolve threads where the underlying issue has been addressed.

#### Reply to unfixed comment threads (requires approval)

For issues that were NOT selected for fixing, draft a reply for each unfixed thread. Present all draft replies to the user for review before posting. Use `AskUserQuestion` with options:

- **Post all replies** -- Send all drafted replies as-is
- **Skip replies** -- Do not post any replies
- **Let me review each** -- Show each reply individually for approval/editing

```bash
# Reply to a review comment
gh api repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies \
  -f body='MESSAGE'
```

Reply messages should be concise and include the classification:

- **Not actionable**: "Not addressing -- this appears to be a style preference rather than a correctness issue. Happy to discuss if the team feels strongly."
- **Deferred (high effort)**: Should include three parts:
  1. **Explanation** -- Why this is being deferred (scope, risk, complexity) and what the issue would involve
  2. **Code fix sketch** -- If the implementation is straightforward, include a brief code snippet showing the recommended fix so a future implementer has a starting point. If there are multiple valid approaches, note the tradeoff and let the user choose.
  3. **Issue recommendation** -- Suggest creating a new issue directly from the comment to track separately.

Do NOT reply to:
- Comments that were resolved (the diff speaks for itself)
- Comments that already have a reply from the current authenticated user (check existing replies in the thread to avoid duplicate responses on repeated invocations)

### 8. Post summary comment

After all fixes, thread resolutions, and replies are complete, post a single summary comment on the PR. This gives reviewers a clear picture of what was addressed and what remains.

Use `AskUserQuestion` to confirm before posting. Show the full rendered comment to the user first.

```bash
# Post PR-level comment
gh api repos/{owner}/{repo}/issues/{pull_number}/comments \
  --raw-field "body=MESSAGE"
```

#### Summary comment format

Use the following template. Every decision falls into one of five buckets. Keep the overall header, the rollup line, and the "Merge Readiness" section; omit any bucket that has no entries.

The five buckets (derived from analyzing real review-cycle decisions across many merged PRs):

1. **Accepted** — fixed in this PR
2. **Rejected (pre-existing)** — flagged code is not introduced by this PR; pre-dates this change
3. **Rejected (out-of-scope per #N)** — valid feedback but explicitly outside the issue's scope contract; tracked separately
4. **Rejected (style)** — debatable style preference, no correctness impact
5. **Deferred (tracked in #N)** — valid feedback, in-scope-adjacent, but resolved through a follow-up issue

```markdown
<!-- pr-fix-summary: status report, not actionable review feedback -->
## Review Feedback Summary

**N accepted · M rejected (pre-existing) · K rejected (out-of-scope per #X) · L rejected (style) · P deferred (tracked in #Y)**

### Accepted

| # | Issue | File | Severity | Reviewer |
|---|-------|------|----------|----------|
| 1 | Description of fix | `path/file.ext#L42` | Blocker | reviewer |

### Rejected — Pre-existing

Findings that pre-date this PR. Not introduced by these changes; addressing them would expand scope.

| # | Issue | File | Severity |
|---|-------|------|----------|
| 1 | Brief description | `path/file.ext#L17` | Warning |

### Rejected — Out of Scope

Valid feedback that falls outside the issue's scope contract. Tracked separately.

| # | Issue | Severity | Scope ref | Track |
|---|-------|----------|-----------|-------|
| 1 | Brief description | Warning | Contract: "Out of Scope — migration changes" | [Create issue](ISSUE_URL) |

### Rejected — Style

Debatable style preferences with no correctness impact.

| # | Issue | Severity | Reason |
|---|-------|----------|--------|
| 1 | Brief description | Suggestion | Style preference, no correctness impact |

### Deferred — Tracked in Follow-up

Valid feedback that will be addressed, but not in this PR. Each entry links to its tracking issue.

| # | Issue | Severity | Why deferred | Track |
|---|-------|----------|--------------|-------|
| 1 | Brief description | Warning | Risk outweighs benefit at this stage | [#NNN](url) |

### Merge Readiness

ASSESSMENT

---
*Generated by `/pr-fix`*
```

#### Rollup line

The bold line under the header is the **rollup**. Include it always — it is the line reviewers actually read. Counts must match the bucket tables exactly. Use zero-counts as `0 accepted` rather than dropping the term.

#### Building issue creation links

For each deferred issue, construct a GitHub "new issue" URL that pre-fills the title and body:

```
https://github.com/{owner}/{repo}/issues/new?title={ENCODED_TITLE}&body={ENCODED_BODY}
```

- **Title**: Short summary of the issue
- **Body**: Include a link to the original review comment, the reviewer's original text (quoted), the classification (severity, effort), and any code fix sketch from the reply

URL-encode the title and body parameters.

#### Merge readiness assessment

Evaluate based on the remaining unaddressed issues:

| Condition | Text |
|-----------|------|
| All issues addressed, tests pass | **Ready to merge** -- all review feedback has been addressed. |
| No blockers remain, some warnings/suggestions deferred | **Ready to merge with follow-ups** -- no blockers remain. N issue(s) deferred for separate tracking. |
| Debatable blockers remain (need discussion) | **Needs discussion** -- N debatable blocker(s) require reviewer input before merging. |
| Unaddressed blockers remain | **Not ready to merge** -- N unresolved blocker(s) remain. |

If tests failed and could not be resolved, always mark as not ready regardless of issue status.

#### Section omission rules

- Omit any of the five buckets when its count is zero
- Always include the rollup line (zero counts shown as `0 accepted`)
- Always include "Merge Readiness" section

## Rules

- This skill is user-invoked only (`/pr-fix`) -- never auto-trigger
- Always read files before editing -- never propose blind changes
- Deduplicate issues that are flagged by multiple reviewers -- note when multiple reviewers agree
- If no PR is found for the current branch, tell the user and stop
- Do not commit changes -- respect the user's commit batching preference
- If the test suite fails after fixes, report the failure and attempt to resolve it
- **Do not prompt to push** if the only actions taken were resolving threads and/or posting replies (no local code changes were made). Only mention pushing when files were actually modified.
- **Never `@` mention bots or users** in the summary comment. Use plain names -- `@` mentions can trigger bot actions or unwanted notifications.
