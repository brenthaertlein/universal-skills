---
name: e2e-write
description: "Generate e2e tests from spec or code analysis with accessibility-first locators and POM conventions."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - AskUserQuestion
  - Agent
  - Edit
  - Write
---

# E2E Test Writer

Generate end-to-end test files from a spec document or code analysis.

## Invocation

`/e2e-write` — generate e2e tests. Looks for a spec file first, falls back to code analysis.
`/e2e-write e2e/specs/login.spec.md` — generate from a specific spec.

## Setup

1. Read `CLAUDE.md` for e2e framework, configuration, and conventions.
2. Find existing e2e tests to learn the project's style.
3. Identify the e2e test runner and its configuration (test directory, base URL, fixtures).

## Locator Strategy (Priority Order)

Use accessibility-first locators:

1. **Role-based**: `getByRole('button', { name: 'Submit' })` or equivalent
2. **Label-based**: `getByLabel('Email')` or equivalent
3. **Text-based**: `getByText('Welcome')` or equivalent
4. **Test ID**: `getByTestId('user-table')` — only as last resort

Use your framework's equivalent APIs if it does not provide these exact methods.

Never use:
- CSS selectors for styling classes (`.btn-primary`, utility-class chains like `.bg-primary.text-white`)
- XPath expressions
- Positional selectors (`:nth-child`)
- Implementation-detail selectors (`[data-state="open"]`)
- Inline class-string selectors derived from production code — couples the test to the visual layer

### Selectors helper

If the project has a `selectors` helper (commonly `e2e/helpers/selectors.ts`, `tests/e2e/selectors.ts`, or framework equivalent), all locators must come from it. Do not inline locators in test files.

- The helper centralizes locator strategy and survives refactors of component markup.
- A test failing because the helper was wrong should fix the helper, not duplicate a workaround locator inline.
- If the project does not yet have a selectors helper and the test introduces a non-trivial locator (more than one chained call, or used in more than one test), create the helper as part of the same change.
- Cross-platform shortcut keys belong in the helper too — `Meta+a` on macOS is `Control+a` on Linux/CI. Centralizing the mapping prevents per-OS test breakage.

## Assertion Patterns

- Assert visible outcomes, not implementation details.
- Use web-first assertions that auto-wait (e.g., `expect(locator).toBeVisible()` or equivalent assertion).
- Assert page URL after navigation.
- Assert accessible names and roles, not CSS classes.
- Verify ARIA attributes for dynamic content (e.g., `aria-expanded`, `aria-selected`).

### Behavior-not-wiring red flags (e2e)

The same anti-patterns from `write-tests` apply to e2e, plus a few that are e2e-specific:

| Red flag in your draft e2e | Reality |
|---|---|
| `if (count > 0) { … }` guard around an interaction | The test passes vacuously when the selector finds nothing — failure mode is silent |
| `await page.locator('.bg-primary')` or other utility-class CSS selector | Tied to the visual layer; refactor-fragile and not what the user sees |
| `await page.waitForTimeout(N)` | Fixed sleep; either too short (flaky) or too long (slow). Use condition-based waits. |
| Reads the boundingBox / pixel position to verify state | Boundary boxes are unreliable across viewports; assert ARIA or visible text |
| Test depends on data left by a previous test | Tests must be isolated (see Test Isolation below) |
| Cross-platform shortcut hardcoded (`Meta+a`) without OS branching | Works on the author's machine; breaks in CI |

For every assertion, write the **state change or side effect** the test verifies into the test name. If you can't, you have one of the anti-patterns above.

## Test Isolation

- Each test must be independent. No test should depend on the state left by another test.
- Use `beforeEach` for setup, not shared mutable state.
- Clean up created data in `afterEach` or use test-scoped fixtures.
- Tests must be runnable in any order and in parallel.

## Page Object Model (POM) Conventions

For complex pages, generate POM classes:

```
e2e/
  pages/
    login.page.ts     — locators and actions for login page
    dashboard.page.ts  — locators and actions for dashboard
  tests/
    login.test.ts      — test cases using page objects
```

POM rules:
- Page objects expose **actions** (methods like `login(user, pass)`) not raw locators.
- Page objects return other page objects for navigation flows.
- Assertions live in test files, not page objects.

## Timeout Conventions

- Navigation: up to 10s.
- API responses: up to 5s.
- Animations: up to 1s.
- Never use fixed `sleep`/`wait` — use condition-based waits.

## Process

1. Read spec file or analyze target page/feature code.
2. Identify test scenarios and user flows.
3. Generate or update POM files if needed.
4. Generate test files with all scenarios.
5. Run the tests to verify they pass.
6. Report results and any issues.
