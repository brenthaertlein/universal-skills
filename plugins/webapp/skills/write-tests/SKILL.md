---
name: write-tests
description: "Generate tests following project conventions with functional test requirements and coverage targets."
user-invocable: true
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

# Write Tests

Generate test files that follow project conventions and exercise real behavior.

## Invocation

`/write-tests` — generate tests for changed files missing coverage.
`/write-tests src/lib/auth.ts` — generate tests for a specific file.

## Setup

1. Read `CLAUDE.md` for test conventions: framework, file naming, directory structure, patterns.
2. Find existing test files to learn the project's test style.
3. Identify the test runner and assertion library from project config.

## Test File Conventions

- **Co-located tests**: Place test files next to source files (e.g., `auth.ts` -> `auth.test.ts`), unless the project uses a separate `__tests__/` directory.
- **Naming**: Match source file name with `.test.` or `.spec.` suffix.
- **Imports**: Follow the project's import style (relative vs. aliases).

## Test Quality Requirements (AAA Pattern)

Every test must follow **Arrange-Act-Assert**:

1. **Arrange**: Set up preconditions and inputs.
2. **Act**: Execute the function/component under test.
3. **Assert**: Verify the expected outcome.

### Functional Test Rules — Tests Must NOT Be:

- **Prop-echo tests**: Tests that just verify a component renders what you pass in (e.g., "renders title" where you pass a title prop and check it appears). Instead, test that the component _behaves_ correctly.
- **Mock-in/mock-out tests**: Tests where you mock the input and then assert the mock was called. This tests nothing. Test real behavior through the mocked boundary.
- **Render-only tests**: Tests that just check a component renders without crashing. Add meaningful assertions about behavior.
- **Shallow assertion tests**: Tests with assertions like `toBeDefined()`, `toBeTruthy()` on complex objects. Assert specific values and shapes.

### Behavior-not-wiring red flags

Before saving a test, scan its assertions against this table. If any apply, the test is testing wiring, not behavior — rewrite or delete it.

| Red flag in your draft test | Reality |
|---|---|
| Asserts only on values passed in via test setup | Prop-echo: verifies the test setup, not the unit under test |
| Mocks a dependency, calls the function, asserts the mock was called with the same args | Mock-in / mock-out: verifies wiring, not behavior |
| Renders a component, checks an element exists, performs no interaction | Render-only: covers a line but no behavior |
| Asserts on a CSS class string | Tests cosmetics; classes change for visual reasons |
| Assertion only checks `toBeDefined()`, `toBeTruthy()`, or array length | Shallow assertion: catches almost no real bug |
| Mocks `Date.now`/the clock and asserts the same `Date.now` | Tautology — tests the mock, not the code |
| `expect(spy).toHaveBeenCalled()` with no follow-up on side effects | Verifies the call happened, not that anything correct followed |
| Test uses `Promise.resolve()` to simulate an in-flight state | Resolves immediately; never exercises the loading/staleness window |

### The behavior question

Every test must answer this question — and the test name must contain the answer:

> **What state change or side effect does this test verify?**

If you can't write the answer in one phrase, the test is one of the anti-patterns above. Rename the test or rewrite it.

Examples:

- ❌ `"renders the user card"` — what behavior is verified?
- ✅ `"shows the user's display name when the profile loads"` — state: profile loads. Behavior: name appears.
- ❌ `"calls onSubmit"` — verifies a call happened.
- ✅ `"submits the form once and disables the button while submitting"` — state: in-flight. Behaviors: one submit, button disabled.

### Mock-state hygiene

- Use a deferred promise (a promise you control with `resolve`/`reject`) when testing loading/in-flight states. `Promise.resolve()` does not exercise the window.
- `clearAllMocks()` resets call history but does **not** reset mock implementations. To reset implementations between tests, set them in `beforeEach` or call `resetAllMocks()` / framework equivalent.
- A fake-timer setup must be paired with a teardown (`useRealTimers()`) — leaked fake timers break unrelated tests in the same worker.

### Tests MUST Exercise:

- **User interactions**: Clicks, form submissions, navigation.
- **State changes**: Verify state transitions produce correct UI/output changes.
- **Error handling**: Invalid inputs, network failures, edge cases.
- **Boundary conditions**: Empty arrays, null values, maximum lengths.
- **Integration points**: Verify components work with their dependencies (use targeted mocks, not total isolation).

## Coverage Targets by Directory

Adapt these to the project's structure:

| Directory     | Target | Priority |
| ------------- | ------ | -------- |
| Data/API layer | 90%   | High     |
| Utils/Lib     | 95%    | High     |
| Hooks         | 85%    | Medium   |
| Components    | 80%    | Medium   |
| Pages/Routes  | 70%    | Lower    |

## TDD Integration

When invoked during a TDD workflow:
1. Write the test first based on the requirements.
2. Verify the test fails (red).
3. Signal that implementation can proceed (the user or another skill handles green).

## Supporting Skills Integration

**`superpowers:test-driven-development`** — If available and you are implementing new functionality, use TDD instead of this skill. TDD writes tests *before* implementation, driving the design from desired behavior and verifying each test fails for the right reason before writing code.

`/write-tests` is the right tool when: adding coverage to *existing* code, filling gaps after implementation, auditing coverage targets by directory, or generating a test scaffold for a file that was written without TDD.

## Process

1. Identify target files needing tests.
2. Read each source file to understand its behavior.
3. Read existing tests in the same directory for style reference.
4. Generate test file with comprehensive test cases.
5. Run the tests to verify they pass (or correctly fail for TDD).
6. Report coverage improvement.
