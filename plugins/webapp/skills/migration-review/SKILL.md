---
name: migration-review
description: "Review database migrations for safety, deploy ordering, and data integrity."
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Migration Review

Review database migrations for production safety.

## Invocation

`/migration-review` — reviews changed migration and schema files.

## Core Principle: Additive Only

Migrations should be **additive by default**. Destructive changes require a two-phase deployment plan.

### Safe Operations (single deploy)
- Add table
- Add column (nullable or with default)
- Add index (concurrent if supported)
- Add constraint (with NOT VALID + separate VALIDATE step for large tables)

### Unsafe Operations (require two-phase plan)
- Drop column — phase 1: stop reading/writing column in code, phase 2: drop column
- Drop table — phase 1: remove all references in code, phase 2: drop table
- Rename column — phase 1: add new column + backfill + read both, phase 2: drop old column
- Change column type — phase 1: add new column with new type + backfill, phase 2: swap
- Add NOT NULL to existing column — phase 1: add CHECK constraint NOT VALID, phase 2: VALIDATE

## Checks

### Migration/Deploy Ordering
- **[FAIL]**: Migration drops a column or table that application code still references.
- **[FAIL]**: Migration adds NOT NULL without a default on an existing column (will fail for existing rows).
- **[WARN]**: Migration and code changes in the same commit that require two-phase deploy.

### Data Migration Rules
- Data migrations must be idempotent (safe to run multiple times).
- Data migrations must handle NULL values.
- Large data migrations should be batched, not single-statement.
- Data migrations should never run inside a DDL transaction.

### Index Safety
- Flag `CREATE INDEX` without `CONCURRENTLY` on large tables (locks table).
- Flag adding multiple indexes in a single migration (extend downtime).

### Rollback Plan
- Verify the migration can be reversed. If not, document why in the migration file.
- Destructive migrations must document the rollback procedure.

### Schema Diff
- Compare the before/after schema to verify the migration produces the intended result.
- Flag unintended side effects (e.g., index accidentally dropped, constraint removed).

## Report Format

```
## Migration Review

- [FAIL] 0042_add_status.sql — adds NOT NULL column without default
- [WARN] 0043_rename_email.sql — column rename should be two-phase
- [PASS] 0044_add_index.sql — uses CREATE INDEX CONCURRENTLY

### Deploy Plan Required: YES
Recommended deploy sequence documented above.
```
