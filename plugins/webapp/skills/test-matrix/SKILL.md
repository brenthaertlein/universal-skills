---
name: test-matrix
description: "Coverage matrix analysis — verify test files exist and are functional for all changed source files."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
---

# Test Matrix

Analyze test coverage completeness for changed source files.

## Invocation

`/test-matrix` — analyze test coverage matrix for files changed on the current branch.

## Process

### 1. Identify Changed Source Files

Get files changed vs. base branch. Filter to source files (exclude tests, configs, docs, generated files).

### 2. For Each Source File, Check:

#### Unit/Integration Test Exists?
- Look for co-located test file (`*.test.*`, `*.spec.*`) or file in `__tests__/` directory.
- **YES** / **NO**

#### Test is Functional?
If a test file exists, read it and assess quality:
- **Functional**: Tests exercise real behavior (interactions, state changes, error handling).
- **Trivial**: Tests only check rendering, prop echoing, or use shallow assertions.
- **Broken**: Test file exists but tests are skipped, commented out, or failing.

#### E2E Coverage? (for user-facing files)
For page/route/view components:
- Check if any e2e test file references this page's URL or key elements.
- **YES** / **NO** / **N/A** (not a user-facing file)

### 3. Generate Matrix

```
## Test Matrix

| Source File              | Unit Test | Quality    | E2E  | Action Needed         |
| ------------------------ | --------- | ---------- | ---- | --------------------- |
| src/lib/auth.ts          | YES       | Functional | N/A  | —                     |
| src/lib/format.ts        | YES       | Trivial    | N/A  | Improve test quality  |
| src/components/Login.tsx | YES       | Functional | YES  | —                     |
| src/api/users.ts         | NO        | —          | NO   | Write unit + e2e test |
| src/hooks/useTheme.ts    | NO        | —          | N/A  | Write unit test       |

### Summary
- **Covered**: 2/5 files (40%)
- **Partial**: 1/5 files (trivial tests)
- **Missing**: 2/5 files
- **E2E Gaps**: 1 user-facing file without e2e coverage

### Recommendations
1. Priority: Write tests for src/api/users.ts (API route, high risk)
2. Priority: Write tests for src/hooks/useTheme.ts (shared hook)
3. Improve: src/lib/format.ts tests are trivial — add edge case coverage
4. E2E: Add e2e coverage for user creation flow
```

## Quality Assessment Criteria

A test is **trivial** if it:
- Only checks that something renders without crashing
- Only asserts `toBeDefined()` or `toBeTruthy()` on complex objects
- Mocks everything and only verifies mocks were called
- Has fewer assertions than the function has code paths

A test is **functional** if it:
- Tests multiple scenarios (happy path + error cases)
- Asserts specific values and behaviors
- Tests user interactions or state transitions
- Covers boundary conditions
