---
name: docs-review
description: "[pr-review-focus-area: Docs] Review documentation for accuracy, completeness, consistency, and LLM context quality."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Documentation Review

Review documentation files for quality, accuracy, and usefulness as LLM context.

## Invocation

`/docs-review` — reviews changed documentation files, or all docs if specified.

## Checks

### Accuracy
- Code examples must match actual project APIs and function signatures.
- File paths referenced in docs must exist in the project.
- Command examples must be runnable (correct flags, correct tool names).
- Version numbers and dependency references must be current.

### Completeness
- Every public API, hook, utility, and component should have documentation.
- Setup instructions must cover all prerequisites.
- Environment variable documentation must list all required variables.
- Migration guides must cover all breaking changes.

### Consistency
- Terminology must be consistent throughout (don't alternate between terms for the same concept).
- Code style in examples must match project conventions.
- Header hierarchy must be logical (no skipping levels).
- Link references must not be broken.

### LLM Context Quality
Documentation should be effective as context for LLMs:
- CLAUDE.md should be a complete, concise project reference.
- Avoid ambiguity and implicit knowledge. State things explicitly.
- Include concrete examples, not just abstract descriptions.
- Organize information hierarchically so partial reads are still useful.

### Style Guide
- Use active voice, present tense.
- Use ATX-style headers (`#`, `##`, `###`).
- One sentence per line in source (for clean diffs).
- Code blocks must specify language for syntax highlighting.
- Lists should be parallel in structure.
- Avoid jargon without definition.

## Report Format

```
## Docs Review

- [WARN] README.md:45 — references `npm run dev:local` but script is `npm run dev`
- [WARN] CLAUDE.md:12 — missing documentation for AUTH_SECRET env var
- [INFO] docs/api.md — good LLM context quality, well-structured

### Summary: 0 FAIL, 2 WARN, 1 INFO
```
