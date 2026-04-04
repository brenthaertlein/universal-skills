---
name: project-status
description: Dashboard of outstanding work — open PRs with CI/review status, critical unstarted issues, and stale branches. Read-only.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Agent, AskUserQuestion
---

# Project Status — Outstanding Work Dashboard

Show the current state of all in-flight and unstarted work to help close out PRs, prioritize critical issues, and surface forgotten branches.

## How to use

Invoke with `/project-status`. No arguments needed. This skill is read-only — it never modifies code, PRs, or issues.

## Phase 1: Gather Data

Run all four of these in parallel.

### 1a. Identify repo context

```bash
gh repo view --json nameWithOwner,url --jq '{nameWithOwner: .nameWithOwner, url: .url}'
```

Parse out the owner, repo name, and base URL. Store for linking throughout.

### 1b. Fetch all open PRs

```bash
gh pr list --state open --limit 30 --json number,title,labels,author,isDraft,createdAt,headRefName,statusCheckRollup,reviewRequests,body
```

### 1c. Fetch all open issues

```bash
gh issue list --state open --limit 50 --json number,title,labels,body,assignees,comments
```

### 1d. Fetch remote branches with last commit dates

```bash
git fetch origin --prune
git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:iso8601) %(subject) %(authorname)' refs/remotes/origin/ | grep -v 'origin/main$\|origin/master$\|origin/HEAD$'
```

This returns all remote branches (excluding main/master/HEAD) with their last commit date, message, and author.

### Linking convention

Throughout all output, render issue and PR numbers as markdown hyperlinks: `[#123](https://github.com/org/repo/issues/123)` for issues, `[#123](https://github.com/org/repo/pull/123)` for PRs. Use the repo URL from step 1a.

## Phase 2: Analyze Each Open PR

For each open PR from step 1b, gather detailed status. **If there are 4+ PRs, use the `Agent` tool with `subagent_type: "Explore"` to analyze multiple PRs in parallel** (one agent per PR, max 3 concurrent). Otherwise, analyze sequentially.

Skip draft PRs for feedback analysis (mark feedback as "N/A").

### 2a. CI Status

Extract from the `statusCheckRollup` field returned in step 1b. Classify:

| CI Status | Condition |
|-----------|-----------|
| **PASS** | All checks have conclusion `SUCCESS` |
| **FAIL: <names>** | Any check has conclusion `FAILURE` — list the failed check names |
| **PENDING** | Any check has state `PENDING` or `IN_PROGRESS` and none have failed |
| **NONE** | No checks configured or empty `statusCheckRollup` |

### 2b. Review Status

For each PR, fetch review state:

```bash
gh api --paginate repos/{owner}/{repo}/pulls/{number}/reviews --jq '[.[] | {state: .state, author: .user.login}]'
```

Classify based on the latest non-COMMENTED review state per reviewer:

| Review Status | Condition |
|---------------|-----------|
| **APPROVED** | At least one APPROVED review and no CHANGES_REQUESTED after it |
| **CHANGES REQ** | Latest review from any reviewer is CHANGES_REQUESTED |
| **PENDING** | Review has been requested but no reviews submitted |
| **NO REVIEW** | No reviews requested or submitted |

### 2c. Feedback Addressed Status

Determine whether outstanding review feedback has been handled using three signals:

#### Signal 1: Unresolved review threads

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
          }
        }
      }
    }
  }
' -f owner=OWNER -f repo=REPO -F pr=NUMBER
```

Count resolved vs unresolved threads.

#### Signal 2: Commits after last review

```bash
# Get timestamp of last review
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '[.[].submitted_at] | sort | last'

# Get timestamp of last commit
gh api repos/{owner}/{repo}/pulls/{number}/commits --jq '[.[].commit.committer.date] | sort | last'
```

If the last commit is newer than the last review, feedback may have been addressed via new commits.

#### Signal 3: Summary comments

```bash
gh api --paginate repos/{owner}/{repo}/issues/{number}/comments --jq '[.[] | select(.body | test("ready to merge|addressed|resolved"; "i")) | {body: .body}]'
```

Check for comments indicating feedback has been addressed.

#### Classify feedback status

| Feedback Status | Condition |
|-----------------|-----------|
| **ALL ADDRESSED** | All threads resolved and APPROVED, or explicit "ready to merge" comment |
| **ADDRESSED (pending re-review)** | New commits exist after last review, most threads resolved |
| **PARTIALLY (N/M resolved)** | Some threads resolved, some unresolved |
| **NOT ADDRESSED** | CHANGES_REQUESTED with no new commits and unresolved threads |
| **NO FEEDBACK** | No reviews or review threads exist |
| **N/A** | PR is a draft |

### 2d. Linked Issue

Scan the PR body and branch name for issue references:
- `Closes #N`, `Fixes #N`, `Resolves #N` (GitHub auto-close keywords)
- Bare `#N` references in the body
- Branch name containing an issue number (e.g., `fix/123-some-feature`)

Store the linked issue number(s) for cross-referencing in Phase 3.

## Phase 3: Identify Unstarted Issues

### 3a. Build a set of "covered" issue numbers

From Phase 2d, collect all issue numbers that have an open PR linked to them.

### 3b. Filter for critical/high-priority unstarted issues

From the open issues list (step 1c), select issues where:
1. The issue number is NOT in the "covered" set from 3a
2. The issue has a `priority: critical` or `priority: high` label (or equivalent priority labels used by the project)

Sort by priority (critical first), then by creation date (oldest first).

### 3c. Count remaining

If there are unstarted issues that are NOT critical/high priority, count them for the footer.

## Phase 4: Identify Stale Branches

Find remote branches that have no open PR and have not been actively worked on.

### 4a. Build a set of branches with open PRs

From Phase 2, collect the `headRefName` of every open PR. These branches are "active" — they have a PR and are covered in Table 1.

### 4b. Filter for stale branches without PRs

From the branch list (step 1d), select branches where:
1. The branch name is NOT in the "has open PR" set from 4a
2. The last commit is **older than 72 hours** from the current time
3. The branch is not `main`, `master`, `HEAD`, or a release/deploy branch (skip branches matching `release/*`, `deploy/*`, `production`)

Sort by last commit date (oldest first — most forgotten at the top).

### 4c. Enrich with context

For each stale branch, extract:
- **Linked issue**: Parse the branch name for issue numbers (e.g., `fix/123-auth-bug` -> `#123`)
- **Commit count ahead of main**: `git rev-list --count origin/main..origin/<branch>`
- **Was it merged?**: Check if the branch was already merged to main: `git branch -r --merged origin/main | grep <branch>`. If merged, mark as "Merged — safe to delete" instead of stale.

### 4d. Check merge compatibility

For each stale (non-merged) branch, check if it can be cleanly merged into main:

```bash
# Dry-run merge to detect conflicts (does NOT modify working tree)
git merge-tree $(git merge-base origin/main origin/<branch>) origin/main origin/<branch>
```

If the output contains conflict markers (`<<<<<<<`), the branch has conflicts. Otherwise it is a clean merge candidate.

For a simpler heuristic when `git merge-tree` output is ambiguous, check divergence:

```bash
# Commits on main that aren't on the branch (how far behind)
git rev-list --count origin/<branch>..origin/main
```

### 4e. Classify branch status

| Status | Condition |
|--------|-----------|
| **STALE — clean merge** | No PR, last commit > 72h, not merged, no conflicts with main |
| **STALE — has conflicts** | No PR, last commit > 72h, not merged, conflicts detected |
| **MERGED (cleanup)** | Branch was merged to main but not deleted |
| **RECENTLY ACTIVE** | No PR but last commit < 72h — skip, not stale yet |

## Phase 5: Present the Dashboard

### Header

```markdown
# Project Status — <repo name>
**As of**: <current date/time>
**Open PRs**: N  |  **Critical unstarted issues**: N  |  **Stale branches**: N  |  **Total open issues**: N
```

### Table 1: Open Pull Requests

Sort by urgency:
1. CHANGES_REQUESTED + NOT ADDRESSED (needs immediate action)
2. CI FAIL (broken builds)
3. APPROVED + CI PASS (ready to merge — easy wins)
4. Everything else by creation date (oldest first)

```markdown
## Open Pull Requests

| PR | Title | Author | CI | Review | Feedback | Linked Issue | Action |
|----|-------|--------|----|--------|----------|--------------|--------|
| [#45](url) | Fix auth redirect | @user | PASS | APPROVED | ALL ADDRESSED | [#42](url) | Ready to merge |
| [#43](url) | Add search feature | @user | FAIL: lint | CHANGES REQ | NOT ADDRESSED | [#38](url) | Fix CI + address feedback |
| [#41](url) | Refactor hooks | @user | PASS | PENDING | NO FEEDBACK | — | Awaiting review |
| [#40](url) | WIP: dark mode | @user | PENDING | NO REVIEW | N/A | [#35](url) | Draft — continue work |
```

#### Column formats

**CI**: PASS / FAIL: <check-name(s)> / PENDING / NONE

**Review**: APPROVED / CHANGES REQ / PENDING / NO REVIEW

**Feedback**: ALL ADDRESSED / ADDRESSED (pending re-review) / PARTIALLY (N/M resolved) / NOT ADDRESSED / NO FEEDBACK / N/A

**Action** — suggest the most relevant next step:
- Merge ready -> "Ready to merge"
- CI failing -> "Fix CI failures"
- Feedback not addressed -> "Address review feedback"
- Awaiting review -> "Awaiting review"
- Draft -> "Continue work, then `/ship-it`"
- Approved but CI failing -> "Fix CI, then merge"

### Table 2: Critical Unstarted Issues

Only issues with critical or high priority labels and no open PR.

```markdown
## Critical Issues — No PR Yet

| Issue | Title | Priority | Labels | Age | Action |
|-------|-------|----------|--------|-----|--------|
| [#50](url) | Security vulnerability in auth | critical | security | 3d | `/start-work 50` |
| [#48](url) | Performance regression on search | high | bug, performance | 5d | `/start-work 48` |
```

If none exist:

```markdown
## Critical Issues — No PR Yet

No critical or high-priority issues without an associated PR.
```

### Table 3: Stale Branches

Branches with no open PR and no commits in the last 72 hours. Sorted by last commit date (oldest first).

```markdown
## Stale Branches — No PR, No Recent Activity

| Branch | Author | Last Commit | Age | Commits Ahead | Merge Status | Linked Issue | Action |
|--------|--------|-------------|-----|---------------|--------------|--------------|--------|
| `fix/123-auth-bug` | @user | "Fix redirect loop" | 5d | 3 | Clean merge | [#123](url) | Open PR — `/ship-it` |
| `feat/456-search` | @user | "Add fuzzy matching" | 2w | 12 | Has conflicts | [#456](url) | Rebase needed |
| `refactor/old-hooks` | @user | "Extract helper" | 3w | 7 | Clean merge | — | Review — ship or delete? |
| `fix/789-typo` | @user | "Fix label text" | 1mo | 1 | Merged | [#789](url) | Safe to delete |
```

#### Merge Status column
- **Clean merge** — no conflicts with current main, could be PR'd as-is
- **Has conflicts** — conflicts detected with main, needs rebase before merging
- **Merged** — already merged to main, branch can be safely deleted

#### Action column
- Clean merge + linked issue -> "Open PR — `/ship-it`"
- Has conflicts -> "Rebase needed"
- No linked issue -> "Review — ship or delete?"
- Already merged -> "Safe to delete"

If no stale branches exist:

```markdown
## Stale Branches — No PR, No Recent Activity

No stale branches found. All active branches have open PRs.
```

### Summary Footer

```markdown
---

### Quick Actions

- **Merge ready PRs**: <list PR numbers that are APPROVED + CI PASS + feedback addressed>
- **PRs needing feedback work**: <list PR numbers with unaddressed feedback>
- **Issues to pick up**: <list top 3 critical unstarted issue numbers> — run `/start-work <number>`
- **Stale branches (clean merge)**: <list branch names that can merge cleanly> — run `/ship-it` after checkout
- **Stale branches (conflicts)**: <list branch names with conflicts> — rebase needed
- **Merged branches to delete**: <list branch names already merged> — `git push origin --delete <branch>`
- **N additional open issues** without PRs — run `/whats-next` to prioritize

### Skill Reference

| Situation | Skill |
|-----------|-------|
| Finish and ship a branch | `/ship-it` |
| Start work on an issue | `/start-work <number>` |
| Pick your next task | `/whats-next` |
```

## Phase 6: Interactive Follow-Up

After presenting the dashboard, use `AskUserQuestion`:

**"What would you like to do next?"**

Options:
1. **Dive into a PR** — "Give me a PR number for detailed status" (show expanded view below)
2. **Start work on an issue** — "Give me an issue number" (hand off to `/start-work`)
3. **Refresh** — Re-run the full dashboard
4. **Done** — Exit

### Handling "Dive into a PR"

If the user selects option 1, ask for the PR number, then show:

```markdown
## PR #<number> — <title>

**Author**: @user  |  **Branch**: `branch-name`  |  **Created**: <date>  |  **Linked Issue**: [#N](url)

### CI Checks
| Check | Status |
|-------|--------|
| <check name> | PASS |
| <check name> | FAIL |

### Review Threads (N resolved / M total)

| # | Status | Reviewer | Summary |
|---|--------|----------|---------|
| 1 | Resolved | @reviewer | Fixed typo in error message |
| 2 | Unresolved | @reviewer | Missing null check in handler |

### Suggested Action
<Specific recommendation based on the analysis>
```

## Rules

- This skill is **read-only** — it never modifies code, creates commits, pushes, or updates PRs/issues
- This skill is user-invoked only (`/project-status`) — never auto-trigger
- Always render issue/PR numbers as clickable markdown hyperlinks
- Use parallel fetches and parallel Agent dispatch (for 4+ PRs) to minimize wait time
- If `gh` CLI is not authenticated or the repo is not a GitHub repo, report the error clearly and stop
- Use GitHub usernames (`@login`), not full names
- Truncate long PR/issue titles in tables to ~50 characters with ellipsis
- Age column should use human-readable relative time (e.g., "2h", "3d", "1w", "2mo")
- Skip feedback analysis for draft PRs — mark as N/A
