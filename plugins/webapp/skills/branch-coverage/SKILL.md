---
name: branch-coverage
description: "Run test coverage scoped to files changed on the current branch and analyze uncovered lines."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Edit
  - Write
---

# Branch Coverage

Run test coverage analysis scoped to files changed on the current branch.

## Invocation

`/branch-coverage` — run coverage for changed files and report gaps.

## Execution Steps

### 1. Identify Changed Files

```
git diff --name-only $(git merge-base HEAD main)..HEAD
```

Filter to source files only (exclude tests, configs, docs). Adjust base branch by checking CLAUDE.md or git remote.

### 2. Run Coverage

Run the project's coverage command (check CLAUDE.md or package.json for `test:coverage`, `coverage`, or equivalent). Scope to changed files if the tool supports it.

If the coverage tool doesn't support file scoping, run full coverage and filter the report to changed files.

### 3. Report for Changed Files

For each changed source file, report:

| File | Statements | Branches | Functions | Lines | Uncovered Lines |
| ---- | ---------- | -------- | --------- | ----- | --------------- |

Highlight files below 80% line coverage.

### 4. Analyze Uncovered Lines

For files with significant uncovered code:
- Read the uncovered line ranges.
- Categorize: error handling paths, edge cases, feature branches, dead code.
- Prioritize: which uncovered lines represent the highest risk?

### 5. Suggest Tests

For each gap, suggest a specific test case:
- What scenario exercises the uncovered code.
- What the expected behavior is.
- Whether it's a unit test or integration test.

## Report Format

```
## Branch Coverage Report

### Changed Files: 8 source files

| File              | Lines | Uncovered          |
| ----------------- | ----- | ------------------ |
| src/lib/auth.ts   | 94%   | 45-48 (error path) |
| src/lib/format.ts | 100%  | —                  |
| src/api/users.ts  | 67%   | 23-30, 55-62       |

### High-Priority Gaps
1. src/api/users.ts:23-30 — validation error branch (no test for invalid input)
2. src/api/users.ts:55-62 — database error handling (no test for connection failure)

### Suggested Tests
1. Test POST /api/users with invalid email format → expect 400
2. Test POST /api/users with database unavailable → expect 500
```
