---
name: api-review
description: "Review API routes for auth, input validation, error handling consistency, HTTP conventions, and test coverage."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# API Route Review

Review API routes for security, correctness, and consistency.

## Invocation

`/api-review` — reviews all changed API route files, or all API routes if no changes detected.

## Setup

1. Read `CLAUDE.md` to identify:
   - The project's API route directory (e.g., `src/app/api/`, `src/routes/`, `pages/api/`, `server/routes/`)
   - The project's auth middleware/wrapper function name
   - The project's standard response helper
   - The project's validation library or pattern
2. Identify changed API route files via `git diff --name-only`.
3. If no changed files, ask the user whether to review all routes or a specific path.

## Checks

### 1. Auth Applied

Every API route must use the project's auth middleware or wrapper (as documented in CLAUDE.md).

- **FAIL**: Route handler has no auth check.
- **WARN**: Route uses auth but in a non-standard way (inline check instead of the project's wrapper).
- **PASS**: Route uses the standard auth pattern, or is explicitly documented as a public endpoint.

### 2. Input Validation

All `POST`, `PUT`, and `PATCH` routes must validate the request body before use.

- **FAIL**: Request body is destructured or accessed without validation.
- **WARN**: Validation exists but does not cover all fields used downstream.
- **PASS**: Body is validated with the project's validation library (e.g., Zod, Joi, class-validator, or a custom schema).

### 3. Error Response Shape

All error responses must follow the project's standard error format.

- **FAIL**: Error responses use inconsistent shapes (some return `{ error }`, others `{ message }`, others raw strings).
- **WARN**: Error responses are consistent but don't use the project's response helper.
- **PASS**: All error responses use the standard helper and shape.

### 4. HTTP Conventions

- `GET` routes return 200, never modify state.
- `POST` routes return 201 for creation, 200 for actions.
- `PUT`/`PATCH` routes return 200.
- `DELETE` routes return 200 or 204.
- 400 for validation errors, 401 for unauthenticated, 403 for unauthorized, 404 for not found, 500 only for unexpected errors.

### 5. Response Typing

No `any` type in response payloads. Response data should be explicitly typed.

- **FAIL**: Response contains `as any`, untyped object literals, or `any` in return type.
- **PASS**: Response is properly typed.

### 6. Test Coverage

Each API route file should have a corresponding test file.

- **FAIL**: No test file exists for the route.
- **WARN**: Test file exists but only tests the happy path (no error cases).
- **PASS**: Test file covers happy path, validation errors, auth failures, and edge cases.

### 7. Senior Review

Dispatch to the `principal-frontend` subagent with the analysis from the prior checks. Ask it to apply its senior lens — type discipline at the boundary, error-handling architecture, auth contract — to the findings. Integrate its top findings into the Report Format below; do not replace the skill's verdict contract.

Invocation:
```
Agent({
  subagent_type: "principal-frontend",
  description: "API route senior review",
  prompt: "Review these API route findings: <summary of auth, validation, error shape, HTTP, typing, and coverage findings from checks 1-6>. Apply senior scrutiny to type discipline at the request/response boundary, error-handling architecture across the route surface, and the auth contract. Return top architectural risks in severity order."
})
```

## Report Format

```
## API Review: /api/users

| Check             | Status | Notes                           |
| ----------------- | ------ | ------------------------------- |
| Auth Applied      | PASS   | Uses standard auth wrapper      |
| Input Validation  | FAIL   | POST body not validated         |
| Error Shape       | PASS   | Consistent error format         |
| HTTP Conventions  | WARN   | POST returns 200, should be 201 |
| Response Typing   | PASS   | All responses typed             |
| Test Coverage     | FAIL   | No test file found              |

### Recommendations
1. Add validation schema for POST /api/users request body
2. Create test file covering auth, validation, and error cases
```

Report each route separately, then provide an overall summary.
