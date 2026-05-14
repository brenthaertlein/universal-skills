---
name: error-handling-preflight
description: "Catch the small set of error-handling pattern violations that account for the majority of production incidents and review-cycle blockers."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Error Handling Preflight

A staff-engineer reflex, expressed as a checklist. The bugs that ship most often are not domain bugs — they're a small set of error-handling pattern violations repeated across files. This skill catches them at draft time so reviewers and bots never have to.

The patterns here are universal: any language with `try/catch`, any runtime with async functions, any API surface that crosses a trust boundary.

## Invocation

- `/error-handling-preflight` — scan the working tree's modified and untracked files
- `/error-handling-preflight <path>` — scan a single file or directory

The skill reports findings; it does not auto-fix. Each finding names the smell, the line, and the fix.

## Scope

Auto-detect targeted files via the project's source extensions (TS/JS/Python/Go/Java/Kotlin/Rust/Ruby/C#). Skip generated code, vendored dependencies, and test fixtures unless explicitly passed in. For language-specific extensions (Next.js, frameworks, runtimes), see the corresponding framework-flavored skill (e.g., `webapp/error-handling-preflight` for Node/web). Always start with the universal checks below.

## Universal Checks

### 1. Unguarded body parsing at trust boundaries

**Smell**: any call that deserializes untrusted bytes (`JSON.parse`, `.json()`, `.parse_*`, `yaml.load`, `xml.parse`, `pickle.loads`, `Form()`) appearing outside a `try`/`catch` (or language equivalent) inside a function that handles external input (HTTP handler, message consumer, IPC entrypoint).

**Why it matters**: malformed input is the most common form of "the service died at 3am". It must produce a structured error, not an uncaught exception.

**Fix**: wrap the parse in try/catch and return (or raise) a structured, sanitized error. Never propagate the parser's native message to the client.

### 2. Floating promises / fire-and-forget async

**Smell**:
- `.then(...)` without a `.catch(...)` (or `.then(ok, err)` second-arg form)
- `await` missing in front of a function call whose return value is a promise the caller cares about
- Top-level `someAsyncFn()` with no `.catch` or `await`
- In task/coroutine APIs: `asyncio.create_task(...)` without a callback to log exceptions; `go fn()` without recover() at the goroutine boundary

**Why it matters**: failures in floating async work disappear silently. The user-visible symptom is "the write didn't happen" with no log.

**Fix**: every async chain ends in a `.catch(observerFn)` or is `await`-ed inside a `try/catch`. Never ignore a rejected promise.

### 3. Async function passed directly to an event-handler slot

**Smell**: `onClick={asyncFn}`, `addEventListener('click', asyncFn)`, signal connections, callback registrations where the consumer does not await the return value.

**Why it matters**: the async function returns a promise that the framework discards. Errors thrown inside the handler are silently swallowed.

**Fix**: wrap in a sync caller — `onClick={() => { void asyncFn().catch(reportErr); }}` — or have the handler explicitly call into a logging boundary.

### 4. Silent catch

**Smell**: `catch (e) { /* nothing */ }` or `catch (e) { return null; }` or `except: pass` with no logging, no metric, no propagation.

**Why it matters**: a swallowed error is an incident with no signal. The deploy is "successful" but the data is wrong.

**Fix**: every catch block produces *at least* one observable side effect: a structured log line, an error metric, a re-thrown wrapped error, or a typed return that the caller is forced to handle. If the error is truly safe to ignore, the catch should comment **why** (one sentence).

### 5. Raw error leaked to clients

**Smell**: returning `error.message`, `String(err)`, `repr(err)`, the exception object, or the stack trace in an HTTP response, RPC reply, or user-facing message.

**Why it matters**: internal errors carry library names, file paths, SQL fragments, and sometimes secrets. They become reconnaissance for attackers.

**Fix**: map errors to a small set of stable user-facing codes/messages. Log the rich error internally; return a sanitized version to the client. The mapping is part of the trust boundary — make it explicit.

### 6. Correlated writes without a transaction

**Smell**: two or more writes to durable storage (DB insert + audit log; DB update + cache write; DB insert + outbox) appearing in sequence with no transactional wrapper. If the second fails, the first is already committed.

**Why it matters**: partial-write incidents are silent until reconciliation. They look like data corruption from above.

**Fix**: wrap correlated writes in a transaction (DB tx, atomic batch). If the writes cross stores (DB + external service), use the outbox pattern — write the intent inside the DB tx, dispatch outside.

### 7. Error narrowing before `.message` / `.code` access

**Smell**: reading `err.message`, `err.code`, `err.statusCode` on a value typed `unknown`/`any`/`Throwable`/`error` without narrowing first.

**Why it matters**: in TypeScript/Python/Go, the catch parameter is not guaranteed to be an `Error` (it can be a string, number, object). Direct field access produces `undefined`/`AttributeError`. The log says "error: undefined".

**Fix**: narrow first. `err instanceof Error ? err.message : String(err)`. `getattr(e, 'message', None) or str(e)`. In Go, type-assert against the concrete error type.

### 8. Null/empty conflation at trust boundaries

**Smell**:
- Server-side validation that checks `value.length === 0` but accepts `"   "` (whitespace) as non-empty
- Coercing optional fields to `""` when the schema says `null`
- `?? ""` or `|| ""` masking a missing value during persistence
- `int(value)` / `Number(value)` without checking for `NaN`/parse failure

**Why it matters**: downstream code can't distinguish "user didn't provide this" from "user provided whitespace". Reports based on the field silently miss rows.

**Fix**: trim before length checks. Preserve `null` through the layer. Validate that conversions succeeded before continuing.

### 9. Retry without idempotency

**Smell**: a retry loop wrapping a write that is not idempotent (POST without an Idempotency-Key; email send; payment authorization).

**Why it matters**: retries amplify the original failure — duplicate charges, duplicate emails, duplicate rows.

**Fix**: retries belong only on operations that carry an idempotency token, or that are inherently safe to repeat (GET, idempotent upsert with a deterministic key). Otherwise retry the *user* by reporting failure and letting them decide.

### 10. Timeout missing on external calls

**Smell**: HTTP client, DB query, RPC call, or message-broker call without an explicit timeout. Defaults vary by library and are often "never".

**Why it matters**: one slow upstream cascades into thread/connection exhaustion. The whole service becomes unavailable.

**Fix**: every external call sets a timeout. The value should be derived from the SLO of the caller, not the library default.

## How to Run

For each universal check, run a grep pattern against the target files. Examples (treat as illustrative — adapt to the project's language and search tool):

```bash
# Floating promises (TypeScript/JavaScript)
rg -n '\.then\([^)]*\)(?!\s*\.catch)' --type ts --type js

# Async passed to event handler
rg -n 'on[A-Z][a-zA-Z]+=\{(async\b|[a-zA-Z_$][a-zA-Z0-9_$]*\s*\})' --type tsx

# Silent catch
rg -n 'catch\s*\([^)]*\)\s*\{\s*\}|except:\s*pass' --type ts --type py

# Raw error to client
rg -n 'res\.(json|send)\([^)]*\berr(or)?\b|Response\([^)]*\bstr\(e\)' --type ts --type py

# Error access without narrowing (TypeScript)
rg -n 'catch\s*\(\s*([a-zA-Z_$]\w*)\s*\)\s*\{[^}]*\1\.(message|code)' --type ts
```

Each finding is reported with: file path, line number, the matched pattern, the rule it violates, and a one-line fix suggestion. Group findings by rule so the user can fix in batches.

## Report Format

```
## Error Handling Preflight

### Findings by rule

**Rule 4 — Silent catch (3 findings)**
- `src/foo.ts:42` — `catch (e) {}` — add a `console.error` or rethrow
- `src/bar.ts:88` — `catch (e) { return null; }` — record metric or return typed Either

**Rule 2 — Floating promises (1 finding)**
- `src/baz.ts:17` — `.then(...)` without `.catch` — chain `.catch(reportErr)`

### Verdict
- BLOCK: 0 findings on critical rules (1, 4, 5, 6)
- WARN: 4 findings on advisory rules

Run `/error-handling-preflight <path>` to scope to one file.
```

Critical rules (block-by-default): 1 (unguarded parse), 4 (silent catch), 5 (raw error leaked), 6 (correlated writes).
Advisory rules: 2, 3, 7, 8, 9, 10 — depend on caller context. Report and let the user decide.

## Rules

1. **Pattern, not opinion.** Every finding cites a rule above. If a finding doesn't fit a rule, this skill is the wrong tool.
2. **Report, don't fix.** Fixes are mechanical but vary by codebase style. The user applies them.
3. **Never silence a real catch by adding a `// silent on purpose` comment unless the user wrote it.** The rationale is a *human* decision.
4. **Framework-specific signatures belong in framework skills**, not here. This skill stays universal; downstream skills (e.g., `webapp/error-handling-preflight`) add Next.js/Express/etc. patterns.
5. **Don't grep test files for these patterns by default.** Tests intentionally exercise error paths and produce false positives.

## Why this exists

Across 90+ PRs reviewed in production teams, error-handling violations were the single most frequently flagged class of issue — more than naming, more than tests, more than design tokens. Every one of these patterns is checklistable. Catching them before a commit prevents:

- Silent data loss from swallowed errors
- Information disclosure from leaked stack traces
- Outages from missing timeouts
- "It worked in the test environment" from missing narrowing

Treat this skill like a linter for the patterns the linter can't catch.
