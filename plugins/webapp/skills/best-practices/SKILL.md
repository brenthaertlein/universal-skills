---
name: best-practices
description: "[pr-review-focus-area: Code Hygiene] Review code for functional style, component composition, hooks/context usage, and general code hygiene."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Best Practices Review

Review changed code for adherence to modern web development best practices.

## Invocation

`/best-practices` — reviews all changed files for code quality patterns.

## Checks

### Functional Style
- Prefer pure functions and immutable data. Flag direct mutations of objects/arrays.
- Prefer declarative patterns (map, filter, reduce) over imperative loops when the result is a transformed collection.
- Avoid side effects in functions that don't need them.
- Use early returns to reduce nesting. Flag functions with more than 3 levels of nesting.

### Single Responsibility
- Functions should do one thing. Flag functions longer than 40 lines.
- Components should render one concept. Flag components longer than 200 lines.
- Files should have one primary export. Flag files with more than 3 unrelated exports.

### Type Safety
- No `any` type usage. Flag every instance.
- No type assertions (`as`) unless accompanied by a comment explaining why.
- Prefer discriminated unions over type widening.
- Function parameters and return types should be explicit for exported functions.

### Naming & Exports
- Use named exports, not default exports (unless the framework requires it).
- Boolean variables/props should use `is`, `has`, `should`, `can` prefixes.
- Event handlers should use `on` prefix (e.g., `onClick`, `onSubmit`).
- Constants should be UPPER_SNAKE_CASE.

### Error Handling
- Async functions must have error handling (try/catch or .catch).
- Never swallow errors silently (empty catch blocks).
- User-facing error messages should be helpful, not raw error strings.

### Code Hygiene
- No commented-out code. Delete it; version control remembers.
- No `console.log` in production code (use the project's logger).
- No magic numbers. Extract to named constants.
- No duplicate logic. Flag copy-pasted blocks of 5+ lines.
- Imports should be organized (framework, external, internal, types).

### Senior Review

Dispatch to the `principal-frontend` subagent with the line-level findings collected above. Ask it to apply its senior lens — composition over configuration, hook discipline, when `useEffect` is a smell — to the findings. Integrate its top findings into the Report Format below; do not replace the skill's verdict contract.

Invocation:
```
Agent({
  subagent_type: "principal-frontend",
  description: "Best-practices senior review",
  prompt: "Review these best-practice findings: <summary of style, SRP, type-safety, naming, error-handling, and hygiene findings>. Apply senior scrutiny to composition over configuration, hook discipline, and cases where useEffect is a smell hiding a deeper design issue. Return top design risks in severity order."
})
```

## Report Format

For each file, list findings as `[WARN]` with the specific line and suggestion. Provide a summary count at the end.
