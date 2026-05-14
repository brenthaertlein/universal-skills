---
name: comment-discipline
description: "Scan added comments in the working diff and flag WHAT-not-WHY comments, paraphrase-of-next-line noise, and other recurring comment anti-patterns."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Grep
  - Bash
---

# Comment Discipline

Code is the source of truth for **what** something does. Comments earn their place by explaining **why** — a hidden constraint, a non-obvious invariant, a workaround for a specific bug, behavior that would surprise a reader. Most comments added during a feature change are noise: paraphrases of the next line, status updates that decay, or references to a PR no one will look up.

This skill scans the working diff for added comments and flags the recurring anti-patterns. It does not delete; it reports.

## Invocation

- `/comment-discipline` — scan added/changed comments in the working diff
- `/comment-discipline --staged` — only scan staged changes
- `/comment-discipline <path>` — scope to a file or directory

## What it scans

Lines beginning with `//`, `#`, `--`, `/*`, ` *`, `<!--`, or the language's comment leader, added in the current diff. Block comments are treated as a single comment for purposes of pattern matching.

```bash
# Use git diff to extract only added comment lines
git diff --unified=0 [--cached] | rg '^\+' | rg -v '^\+\+\+' | rg '^\+\s*(//|#|--|\*|<!--|/\*)'
```

## Anti-patterns to flag

### C1. Paraphrase of the next line

The comment restates the next line in English. Removing the comment loses no information.

**Smell:**
```ts
// Increment the counter
counter++;

// Return the user
return user;

// Loop over the items
for (const item of items) { … }
```

**Fix**: delete the comment. The code already says this.

### C2. Multi-line block where one line would do

A multi-paragraph JSDoc/docstring that doesn't add information not already in the function signature or name.

**Smell:**
```ts
/**
 * Computes the sum.
 *
 * @param a The first number
 * @param b The second number
 * @returns The sum of a and b
 */
function sum(a: number, b: number): number { … }
```

**Fix**: delete the doc block. The types and the function name already say this. Reserve doc blocks for non-obvious behavior, constraints, or invariants that aren't in the signature.

### C3. Stale module-level claim

A top-of-file comment that makes a factual claim about the module's behavior, structure, or constraints — and that claim is now untrue (or was never true).

**Smell:**
```ts
// This module has no external dependencies.
import { z } from "zod";
import { redis } from "@/lib/redis";
```

**Fix**: delete it, or rewrite to be true. Stale claims are worse than no comment — they actively mislead.

To detect, look for absolute claims (`no`, `only`, `never`, `always`, `must`) and verify against the current file content.

### C4. References to the current PR/task/caller

Comments tying the code to ephemeral context that will rot.

**Smell:**
```ts
// Added for issue #1234
// Used by the onboarding flow
// See PR #5678 for context
// TODO(name): fix this before launch
```

**Fix**: delete. PR descriptions and `git blame` carry this context durably. Comments inside code outlive PRs and grow misleading.

**Exception**: a comment that explains a *constraint* the caller imposed (e.g., "Callers expect this to be idempotent — see invariant in `userService`") is fine. The distinction: explains a contract vs. names a caller.

### C5. `eslint-disable` / suppression without rationale

A linter suppression with no explanation.

**Smell:**
```ts
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const data: any = response;

// @ts-ignore
config.unsafe = true;
```

**Fix**: add a one-line rationale after the rule name:

```ts
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- third-party lib emits untyped JSON
const data: any = response;
```

A suppression without rationale is technical debt with no expiration date. With rationale, it becomes a decision the next reader can evaluate.

### C6. "Commented-out" code

Code that was disabled by adding `//` rather than deleted.

**Smell:**
```ts
// const oldConfig = loadConfig();
// processWithOldConfig(oldConfig);
const newConfig = loadConfigV2();
```

**Fix**: delete the commented lines. Version control remembers; the file should not.

### C7. "Removed X" / "Used to do Y" / changelog comments

Comments narrating the change.

**Smell:**
```ts
// Removed the old retry logic
function send() { … }

// Was using setTimeout, switched to setInterval
const id = setInterval(tick, 1000);
```

**Fix**: delete. The PR description and commit message carry this. Inside the code it ages immediately.

## Patterns to *preserve* (not flagged)

- **WHY comments**: explain a constraint, an invariant, a workaround, or a surprising behavior.
- **Citation comments**: reference an external spec, RFC, or upstream bug that the code is working around.
- **Performance commentary**: explain why the obvious refactor would regress (e.g., "avoiding allocations in the hot path").
- **Safety markers**: `// SAFETY: …` in unsafe Rust blocks; `// PRECONDITION: …` on a function that asserts on caller behavior.
- **Section markers** in large files when navigation would otherwise be painful (use sparingly).

If a comment fits one of these and starts with a clue word (`Why`, `Reason`, `Note`, `Workaround`, `SAFETY`, `PRECONDITION`, `Invariant`, `Spec:`, `Bug:`), it should pass.

## How to run

```bash
# 1. Extract added comment lines from the diff
added_comments=$(git diff --unified=0 ${STAGED:+--cached} -- $TARGET \
  | rg '^\+' | rg -v '^\+\+\+' \
  | rg '^\+\s*(//|#|--|\*|<!--|/\*)' )

# 2. For each comment, run the anti-pattern matchers:
#    - C1: comment followed by single line that contains words from the comment (paraphrase heuristic)
#    - C2: block comment with 4+ lines and no Why/Note/Invariant/Safety keyword
#    - C3: top-of-file absolute claim — verify against file content
#    - C4: contains "issue #", "PR #", "for the ... flow", "added for", "used by"
#    - C5: contains "eslint-disable" or "@ts-ignore" with no "--" rationale separator
#    - C6: comment line whose content parses as valid code (heuristic: contains "=", "(", or ";")
#    - C7: starts with "Removed", "Was", "Used to", "Changed from", "Refactored"
```

The paraphrase heuristic (C1) is approximate: tokenize the comment and the next line of code, lowercase, and check overlap. ≥50% overlap of the comment's content words with identifiers/keywords on the next line is a flag. False positives are acceptable — the user makes the final call.

## Report Format

```
## Comment Discipline

### Findings (N)

**C1 — Paraphrases next line (3)**
- `src/foo.ts:42` — `// Increment the counter` → `counter++`
- `src/foo.ts:88` — `// Return the user` → `return user;`

**C5 — Suppression without rationale (1)**
- `src/bar.ts:17` — `eslint-disable-next-line @typescript-eslint/no-explicit-any` (no `--` rationale)

**C7 — Changelog comment (1)**
- `src/baz.ts:5` — `// Refactored from old retry logic`

### Verdict
Recommend deleting or rewriting the N findings above. None are auto-fixed.
```

## Rules

1. **Report, don't auto-fix.** Comment deletion is a judgment call the human owns.
2. **Pattern-based only.** If a finding doesn't fit C1–C7, it's not flagged. Comment style is opinionated; the skill is constrained.
3. **Don't scan test files by default** — tests often carry explanatory commentary that violates these patterns intentionally.
4. **Don't scan auto-generated files** (codegen, `.d.ts` outputs, migration scaffolds).
5. **Preserve language-required leading comments** — license headers, shebangs, framework-required directives.

## Why this exists

The default-system-prompt rule "no WHAT comments" is well-known and frequently violated — including by tools and agents that paraphrase the next line out of habit. Each violation is small; the cumulative effect is a codebase narrated in two redundant languages.

Catching this at draft time is one of the cheapest possible quality wins. The patterns above cover the vast majority of comment-noise findings raised in code review.
