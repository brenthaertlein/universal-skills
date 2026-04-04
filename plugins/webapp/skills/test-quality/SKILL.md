---
name: test-quality
description: "Assess test quality by detecting anti-patterns and verifying tests exercise real behavior."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Test Quality Review

Assess the quality of existing tests by detecting anti-patterns and verifying tests exercise real behavior.

## Invocation

`/test-quality` — review quality of test files for changed source files, or all tests if specified.

## Anti-Pattern Detection

> Examples shown in React/Jest syntax. Adapt patterns to your framework's equivalent APIs.

### Prop-Echo Tests
Tests that just verify a component renders what you pass in.
```
// BAD: just echoing the prop back
render(<Title text="Hello" />)
expect(screen.getByText("Hello")).toBeInTheDocument()
```
Flag when the only assertion is checking that a passed prop appears in output.

### Mock-In / Mock-Out Tests
Tests where you mock the input and assert the mock was called, testing nothing real.
```
// BAD: mock in, mock out
const mockFn = jest.fn()
doThing(mockFn)
expect(mockFn).toHaveBeenCalled()
```
Flag when mocks are both the input and the assertion target.

### Render-Only Tests
Tests that just check a component renders without crashing, with no meaningful assertions.
```
// BAD: render-only
it('renders', () => {
  render(<Dashboard />)
})
```
Flag tests with zero assertions or only `expect(container).toBeDefined()`.

### Shallow Assertions
Tests that use weak assertions that would pass for almost any value.
- `toBeDefined()` on complex objects
- `toBeTruthy()` on non-boolean values
- `toHaveLength()` without checking content
- `toContain()` with trivial substrings

### Over-Mocking
Tests that mock so many dependencies that they test nothing real.
- Flag tests with more than 5 mocks.
- Flag tests where all imported modules are mocked.
- Flag tests that mock the module under test.

### Test Duplication
- Flag tests with identical or near-identical setup and assertions.
- Suggest parameterized tests or shared fixtures.

## Positive Quality Indicators

Tests should exercise:
- **User interactions**: Click, type, submit, navigate.
- **State changes**: Before/after comparisons, UI updates after actions.
- **Error handling**: Invalid inputs, API failures, boundary conditions.
- **Integration**: Components working with real (or minimally mocked) dependencies.
- **Accessibility**: ARIA roles, keyboard navigation, screen reader text.

## Report Format

```
## Test Quality Report

### Anti-Patterns Found
- [WARN] src/components/__tests__/Button.test.tsx — prop-echo test (3 tests just check rendered text matches props)
- [WARN] src/lib/__tests__/api.test.ts — mock-in/mock-out (2 tests only verify mock calls)
- [WARN] src/pages/__tests__/Home.test.tsx — render-only (1 test with no assertions)

### Quality Scores
| Test File                  | Tests | Anti-Patterns | Functional | Score  |
| -------------------------- | ----- | ------------- | ---------- | ------ |
| Button.test.tsx            | 5     | 3             | 2          | 40%    |
| api.test.ts                | 8     | 2             | 6          | 75%    |
| Home.test.tsx              | 3     | 1             | 2          | 67%    |

### Overall: 61% functional (10/16 tests exercise real behavior)

### Recommendations
1. Button.test.tsx: Add interaction tests (click handlers, disabled state, loading state)
2. api.test.ts: Replace mock-only tests with integration tests using MSW or similar
3. Home.test.tsx: Add assertions for page content, navigation, and error state
```
