---
name: e2e-spec
description: "Generate behavioral specification for e2e tests through interactive questionnaire."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - AskUserQuestion
  - Agent
  - Write
---

# E2E Spec Generator

Generate a behavioral specification document for end-to-end tests through an interactive questionnaire.

## Invocation

`/e2e-spec` — start the spec generation process for a page or feature.

## Process

### 1. Scope Detection

Identify the target for e2e testing:

- If the user specifies a page/feature, use that.
- Otherwise, detect changed page/route files and suggest candidates.
- Read the target files to understand the UI, user flows, and data dependencies.

### 2. Smart Questionnaire

Ask the user targeted questions to build the spec. Use `AskUserQuestion` for each category. Skip categories the user marks as not applicable.

#### User Journeys
- What are the primary user flows for this page/feature?
- What roles/permissions are involved?
- What are the entry points (direct URL, navigation, deep link)?
- What is the expected happy-path sequence?

#### Accessibility
- Should we test keyboard navigation?
- Are there ARIA roles or labels to verify?
- Should screen reader announcements be tested?
- Color contrast requirements?

#### Visual / Layout
- Which viewports matter? (mobile, tablet, desktop)
- Are there responsive breakpoints to test?
- Any animations or transitions to verify?
- Dark/light mode testing needed?

#### Error States
- What happens when the API returns an error?
- What happens with invalid form input?
- What happens when the user is unauthorized?
- Offline/timeout behavior?

#### Data Edge Cases
- Empty state (no data)?
- Single item vs. many items?
- Maximum data (pagination, truncation)?
- Special characters in inputs?

#### Performance
- Maximum acceptable load time?
- Any lazy-loading to verify?
- Pagination or infinite scroll behavior?

### 3. Spec Document Generation

Write the spec to a file (e.g., `e2e/specs/{feature-name}.spec.md`).

#### Spec Format

```markdown
# E2E Spec: {Feature Name}

## Scope
- Pages: {list of pages/routes}
- Roles: {list of user roles}
- Viewports: {list of viewports}

## User Journeys

### Journey 1: {Name}
**Preconditions**: {setup required}
**Steps**:
1. Navigate to {URL}
2. {action}
3. {action}
**Expected**: {outcome}
**Tags**: [smoke] [critical-path]

### Journey 2: {Name}
...

## Error Scenarios
...

## Accessibility Tests
...

## Visual / Layout Tests
...

## Data Edge Cases
...

## Performance Criteria
...
```

#### Tags

Use configurable tags to categorize tests. Common tags:
- `[smoke]` — critical path, run on every deploy
- `[critical-path]` — core user journey
- `[regression]` — previously broken, must not regress
- `[accessibility]` — a11y specific
- `[visual]` — layout/visual regression
- `[edge-case]` — data boundary tests

Users can define custom tags in CLAUDE.md.

### 4. Review

Present the generated spec to the user for review and iterate based on feedback.
