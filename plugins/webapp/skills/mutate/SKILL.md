---
name: mutate
description: "Run mutation testing to verify test effectiveness by analyzing killed, survived, and uncovered mutants."
user-invocable: true
argument-hint: "[changed | path | full]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
---

# Mutation Testing

Run mutation testing to verify that tests actually detect bugs, not just execute code.

## Invocation

- `/mutate` or `/mutate changed` — mutate files changed on the current branch
- `/mutate src/lib/auth.ts` — mutate a specific file or directory
- `/mutate full` — mutate all source files (warning: slow)

## What is Mutation Testing?

Mutation testing modifies source code (creates "mutants") and runs tests. If tests fail, the mutant is **killed** (good). If tests pass despite the mutation, the mutant **survived** (bad — tests are weak).

## Setup

1. Read `CLAUDE.md` for the mutation testing tool (e.g., Stryker, mutmut, cargo-mutants, or equivalent).
2. If no mutation tool is configured, suggest installing one appropriate for the project's language.
3. Identify the configuration file if it exists.

## Execution

### Scope Detection

| Argument   | Behavior                                             |
| ---------- | ---------------------------------------------------- |
| `changed`  | Files changed vs. base branch (`git diff --name-only $(git merge-base HEAD main)..HEAD`) |
| `{path}`   | Specific file or directory                           |
| `full`     | All source files (warn about duration first)         |

Filter to source files only. Exclude tests, configs, generated files, and type definition files.

### Run Mutations

Execute the project's mutation testing tool scoped to the target files.

## Result Analysis

### Categories

- **Killed**: Mutant detected by tests. Good.
- **Survived**: Mutant NOT detected. Tests are insufficient for this code path.
- **No Coverage**: Code has no tests at all. Worse than survived.
- **Timeout**: Mutant caused an infinite loop. Treated as killed.
- **Error**: Mutant caused a compilation error. Ignored.

### Mutation Score

```
Mutation Score = Killed / (Killed + Survived + No Coverage) * 100
```

Target: 80%+ for critical code, 60%+ for general code.

### Surviving Mutant Analysis

For each survived mutant:
1. Show the original code and the mutation.
2. Explain what behavior change the mutation represents.
3. Suggest a specific test that would kill this mutant.

## Report Format

```
## Mutation Testing Report

### Scope: 5 files (changed)

| File              | Mutants | Killed | Survived | Score |
| ----------------- | ------- | ------ | -------- | ----- |
| src/lib/auth.ts   | 12      | 11     | 1        | 92%   |
| src/lib/format.ts | 8       | 8      | 0        | 100%  |
| src/api/users.ts  | 15      | 9      | 6        | 60%   |

**Overall Score: 80% (28/35)**

### Surviving Mutants

#### src/api/users.ts:42
- **Mutation**: Changed `>=` to `>` in age validation
- **Impact**: Off-by-one error in minimum age check would go undetected
- **Suggested test**: Test with age exactly equal to minimum (boundary value)

#### src/api/users.ts:58
- **Mutation**: Removed null check on `user.email`
- **Impact**: NullPointerException for users without email would go undetected
- **Suggested test**: Test with user object missing email field
```
