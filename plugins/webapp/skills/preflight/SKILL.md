---
name: preflight
description: "Web app quality gate \u2014 lint, typecheck, unit tests, e2e tests, coverage, and migration review."
user-invocable: true
argument-hint: "[--fix]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Edit
  - Write
  - Agent
---

# Web App Preflight Check

Quality gate for web application changes. Validates code quality, type safety, test coverage, and migration safety before committing.

## Invocation

- `/preflight` — run all checks in read-only mode
- `/preflight --fix` — attempt auto-fixes for type errors and missing tests

## Execution Order

Run checks sequentially. Each check depends on the previous passing (except where noted).

### 1. Lint

Run the project's lint command.

- Check `CLAUDE.md` for the lint command, or look in `package.json` scripts for `lint`, or detect the linter config (`.eslintrc*`, `biome.json`, `.prettierrc*`, etc.).
- Report: number of warnings and errors.
- If `--fix` is passed: run the lint fix command (e.g., the `lint:fix` script).

### 2. Format Check

Run the project's format check command.

- Check `CLAUDE.md` or `package.json` scripts for `format:check`, `format`, or detect formatter config.
- Report: number of files needing formatting.
- If `--fix` is passed: run the format fix command.

### 3. Type Check

Run the project's type checker.

- Check `CLAUDE.md` or detect `tsconfig.json`, `jsconfig.json`, `pyproject.toml` (for Python type checkers), etc.
- Report: number of type errors with file locations.
- If `--fix` is passed: attempt to fix type errors by analyzing each error and applying corrections. After fixes, re-run the type checker to verify.

### 4. Unit Tests

Run the project's unit test suite.

- Check `CLAUDE.md` or `package.json` scripts for `test`, `test:unit`, or detect test runner config.
- Report: total tests, passed, failed, skipped.
- Do NOT auto-fix failing tests (even with `--fix`).

### 5. E2E Tests

Run the project's end-to-end test suite.

- Check `CLAUDE.md` or `package.json` scripts for `test:e2e`, `e2e`, or detect e2e config.
- Report: total tests, passed, failed, skipped.
- If no e2e test suite is configured, mark as N/A.

### 6. Test Matrix

Analyze test coverage for changed files:

- For each changed source file, check whether a corresponding test file exists.
- Categorize: **covered** (test exists and is functional), **partial** (test exists but trivial), **missing** (no test file).
- If `--fix` is passed: generate skeleton test files for missing coverage using the `write-tests` skill if available.

### 7. Migration Review

Triggered only if schema or migration files have changed.

- Detect migration files by looking for common patterns: `migrations/`, `drizzle/`, `prisma/migrations/`, `alembic/`, `db/migrate/`, `*.sql` in migration directories.
- If migration files changed, run the `migration-review` skill checks inline:
  - Verify additive-only changes (no column drops, table drops, or type changes without a migration plan).
  - Check migration/deploy ordering safety.
  - Flag destructive operations.

### 8. Summary

```
## Preflight Summary

| Check            | Status | Details                      |
| ---------------- | ------ | ---------------------------- |
| Lint             | PASS   | 0 errors, 3 warnings        |
| Format           | PASS   | all files formatted          |
| Type Check       | PASS   | 0 errors                    |
| Unit Tests       | PASS   | 142/142 passed               |
| E2E Tests        | PASS   | 28/28 passed                 |
| Test Matrix      | WARN   | 2 files missing tests        |
| Migration Review | N/A    | no schema changes            |

**Verdict: GO** (0 failures, 1 advisory warning)
```

## Verdict Rules

- **GO**: All checks PASS or N/A. Advisory warnings from Test Matrix do not block.
- **NO-GO**: Any of Lint, Format, Type Check, Unit Tests, or E2E Tests is FAIL.
- **GO WITH WARNINGS**: All critical checks pass but Test Matrix or Migration Review has warnings.

## Rules

1. **Detect, don't assume**: Always check CLAUDE.md and project config files for the correct commands. Never hardcode a specific tool or framework.
2. **Fail fast**: If lint fails, still run remaining checks but report NO-GO.
3. **Auto-fix scope**: With `--fix`, only fix lint, format, and type errors. Never auto-fix failing tests.
4. **Re-verify after fix**: If `--fix` made changes, re-run the affected check to confirm the fix worked.
