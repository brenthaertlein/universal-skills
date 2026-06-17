---
name: drizzle-sql-migration
description: "Use when writing or applying Drizzle ORM database migrations — schema changes (DDL) and data fixes (DML custom migrations)."
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Edit
  - Write
---

# Drizzle SQL Migration

A focused guide for writing and applying Drizzle ORM database migrations, covering both schema changes (DDL) and data fixes (DML custom migrations).

## How Drizzle Migrations Work

- Migrations live in a migrations directory (commonly `drizzle/`). Check `drizzle.config.ts` for the configured path.
- Each migration is a `.sql` file with a timestamp-based name.
- Drizzle tracks applied migrations via the `__drizzle_migrations` table in the database.
- Two ways to create migrations:
  - `npx drizzle-kit generate` — diffs your schema file against the last snapshot and writes SQL automatically (for DDL/schema changes).
  - `npx drizzle-kit generate --custom` — creates an empty `.sql` file for you to fill in (for DML/data fixes).

## Creating a Schema Migration (DDL)

Step by step:

1. **Modify the schema file.** Add a column, add a table, change a type, etc. Find the schema file by checking `drizzle.config.ts` for the `schema` field.
2. **Generate the migration:**
   ```bash
   npx drizzle-kit generate
   ```
   Drizzle diffs the current schema against its last snapshot and writes the SQL migration file.
3. **Review the generated SQL.** Open the new file in `drizzle/` and verify the SQL is correct. Pay special attention to renames — Drizzle may generate a `DROP COLUMN` + `ADD COLUMN` instead of `ALTER TABLE ... RENAME COLUMN`. Fix if needed.
4. **Apply the migration:**
   ```bash
   npx drizzle-kit migrate
   ```
5. **Verify** the change took effect (e.g., check the table in a database client or run a quick query).

## Creating a Custom/Data Migration (DML)

Step by step:

1. **Generate an empty migration file:**
   ```bash
   npx drizzle-kit generate --custom --name=describe-what-it-does
   ```
2. **Open the generated file** and write your SQL. Example:
   ```sql
   UPDATE users SET status = 'active' WHERE status IS NULL;
   ```
3. **Apply the migration:**
   ```bash
   npx drizzle-kit migrate
   ```
4. **Verify** with a SELECT to confirm the data looks correct.

## Safety Rules

- **Never edit an existing migration file** that has already been applied. If you need to fix something, create a new migration.
- **DML migrations don't need a snapshot** — they are custom SQL files that Drizzle runs as-is.
- **Wrap risky data changes in a transaction:**
  ```sql
  BEGIN;
  UPDATE accounts SET balance = balance * 1.05 WHERE tier = 'premium';
  -- Verify row count before committing
  COMMIT;
  ```
- **Test on staging first** before applying to production.
- **Never combine DDL and DML in the same migration file.** Schema changes and data fixes should be separate migrations so they can be reasoned about and rolled back independently.

## Common Patterns

### Adding a NOT NULL Column

You cannot add a `NOT NULL` column to a table that already has rows without a default. Use a three-step approach:

1. Add the column as **nullable** (schema migration).
2. **Backfill** existing rows (custom/data migration).
3. **Alter** the column to `NOT NULL` (schema migration).

### Renaming a Column

Drizzle does not detect renames. When you rename a column in the schema file, `drizzle-kit generate` will produce a `DROP COLUMN` + `ADD COLUMN`, which destroys data.

Fix: edit the generated SQL and replace the DROP/ADD with:
```sql
ALTER TABLE "my_table" RENAME COLUMN "old_name" TO "new_name";
```

### Large Table Indexes

For tables with >100k rows, `CREATE INDEX` locks the table. Use a custom migration instead:

1. `npx drizzle-kit generate --custom --name=add-index-concurrently`
2. Write:
   ```sql
   CREATE INDEX CONCURRENTLY "idx_name" ON "my_table" ("column_name");
   ```
   Note: `CONCURRENTLY` cannot run inside a transaction. Ensure your migration runner does not wrap this in a transaction block.

## Senior Review (before applying)

Before applying a generated migration to anything beyond local dev — especially one touching a large or high-traffic table — dispatch the migration SQL to the `data-engineer` subagent for a safety pass. Ask it to check lock behavior and duration at production row counts, zero-downtime (expand/contract) compatibility with currently-running code, backfill strategy for any data change, and whether the rollback path is sound. Act on its findings before you run the migration; it reviews, it does not apply.

```
Agent({
  subagent_type: "data-engineer",
  description: "Migration safety review",
  prompt: "Review this Drizzle migration before it is applied: <the generated SQL and the table's approximate row count if known>. Assess lock type and duration at production scale, zero-downtime compatibility with old code still running during rollout, backfill safety for any data change, and the rollback path. Return blocking risks first, then hardening suggestions, quoting the specific statement for each."
})
```
