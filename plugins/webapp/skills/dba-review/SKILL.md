---
name: dba-review
description: "[pr-review-focus-area: Database] Database schema and query audit for correctness, performance, and conventions."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# DBA Review

Audit database schemas and queries for correctness, performance, and naming conventions.

## Invocation

`/dba-review` — reviews changed schema and query files.

## Schema Checks

### Foreign Key Indexes
- Every foreign key column must have an index. Flag missing indexes as **[FAIL]**.
- Composite foreign keys need composite indexes in the correct column order.

### Data Type Rules
- Prefer `text` over `varchar` unless a strict length constraint is required.
- Use `timestamptz` (timestamp with time zone), never `timestamp` without timezone.
- Use `bigint` / `bigserial` for primary keys on tables expected to grow unbounded.
- Use `jsonb` over `json` for any JSON column (supports indexing and operators).
- Use `uuid` type for UUID columns, not `text` or `varchar(36)`.
- Boolean columns should be `boolean`, not `int` or `smallint`.

### Naming Conventions
- Table names: `snake_case`, plural (e.g., `users`, `order_items`).
- Column names: `snake_case`, singular descriptive (e.g., `created_at`, `user_id`).
- Index names: `idx_{table}_{columns}`.
- Foreign keys: `fk_{table}_{referenced_table}` or `{referenced_table}_id` column name.
- Avoid reserved words as identifiers.

### Constraints
- Every table must have a primary key.
- Use `NOT NULL` unless the column genuinely needs to be nullable. Flag nullable columns without justification.
- Add `CHECK` constraints for columns with bounded values (e.g., `status`, `priority`).
- Use `UNIQUE` constraints where business rules require uniqueness.

## Query Checks

### Anti-Patterns
- **N+1 queries**: Flag loops that execute a query per iteration. Suggest batch/join.
- **SELECT ***: Flag usage. Specify columns explicitly.
- **Missing WHERE**: Flag `UPDATE` or `DELETE` without a `WHERE` clause as **[BLOCK]**.
- **Unbounded queries**: Flag `SELECT` without `LIMIT` on potentially large tables.
- **String concatenation in queries**: Flag SQL injection risks. Use parameterized queries.

### Performance
- Flag queries joining more than 4 tables without clear need.
- Flag `LIKE '%value%'` (leading wildcard prevents index usage).
- Flag missing indexes on columns used in `WHERE`, `JOIN`, or `ORDER BY`.
- Flag `ORDER BY` on unindexed columns for large tables.

## Senior Review

After the schema and query checks, dispatch to the `data-engineer` subagent with the findings. Ask it to apply its data-layer lens — index/query hygiene confirmed against the plan where possible, integrity guarantees that belong in the schema, and behavior at production row counts rather than dev scale — and to rank what it would block on. Integrate its top findings into the report below; do not replace the skill's [BLOCK]/[FAIL]/[WARN] verdict contract.

```
Agent({
  subagent_type: "data-engineer",
  description: "DBA senior review",
  prompt: "Review these database findings: <schema and query issues with table/column/path:line>. Apply senior data-engineer scrutiny — index and query hygiene at production scale, integrity constraints that belong in the schema, N+1 and unbounded-result risks. Rank what you would block on versus hardening. Return findings in severity order, quoting the table, column, or query for each."
})
```

## Report Format

```
## DBA Review

### Schema Issues
- [FAIL] users table: FK column `org_id` has no index
- [WARN] posts table: `created_at` uses `timestamp`, should be `timestamptz`

### Query Issues
- [BLOCK] src/data/users.ts:42 — DELETE without WHERE clause
- [WARN] src/data/posts.ts:18 — SELECT * should specify columns
- [WARN] src/data/orders.ts:55 — N+1 query pattern in loop

### Summary: 1 BLOCK, 1 FAIL, 3 WARN
```
