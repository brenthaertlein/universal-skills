---
name: architecture-review
description: "Review code for server/client boundary violations, import direction issues, and file placement conventions."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Architecture Review

Review codebase for structural violations: server/client boundaries, import direction, file placement, and component patterns.

## Invocation

`/architecture-review` — reviews changed files for architectural violations.

## Setup

1. Read `CLAUDE.md` to identify:
   - Framework-specific client/server boundary directives (e.g., `"use client"`, `"use server"`, decorators)
   - Layer definitions and import rules
   - File placement conventions
   - Database access patterns
2. Identify changed files via `git diff --name-only`.

## Checks

### 1. Server/Client Boundary

Files that use client-only APIs (browser globals, DOM manipulation, event handlers, client state hooks) must be explicitly marked as client components using the framework's directive.

- **FAIL**: File uses client-only APIs but is not marked as a client component.
- **FAIL**: File marked as client component imports server-only modules (database, fs, server secrets).
- **WARN**: File marked as client component but contains no client-only code (unnecessary directive).
- **PASS**: Boundary directives match actual usage.

### 2. Import Direction

Enforce layering rules. Lower layers must not import from higher layers:

```
DB / Data layer        (lowest)
  |
Lib / Utils
  |
Hooks / Services
  |
Components
  |
Pages / Routes         (highest)
```

- **FAIL**: Database layer imports from components or hooks.
- **FAIL**: Lib/utils imports from hooks or components.
- **FAIL**: Circular dependency detected between layers.
- **WARN**: Hooks import directly from the database layer (should go through a service/data layer).

Adapt layer names to the project's actual directory structure.

### 3. File Placement

Files should live in their conventional directories:

| Type       | Expected location                     |
| ---------- | ------------------------------------- |
| Hooks      | `hooks/`, `*/hooks/`                  |
| Constants  | `constants/`, `*/constants/`, `config/` |
| Types      | `types/`, `*/types/`                  |
| Utils      | `utils/`, `lib/`, `*/utils/`          |
| Components | `components/`, `*/components/`        |
| Tests      | Co-located or in `__tests__/`         |

- **WARN**: Hook defined outside a hooks directory.
- **WARN**: Type definitions mixed into component files (should be extracted if reused).
- **WARN**: Utility function defined inside a component file.

### 4. Database Access Pattern

Database queries and ORM calls must only appear in server-side code.

- **FAIL**: Database import or query in a client-marked file.
- **FAIL**: Database import in a component file that could run on the client.
- **PASS**: All database access is in server-side data layer files.

### 5. Component Patterns

- **Single responsibility**: Components should do one thing. Flag components over 200 lines or with multiple unrelated responsibilities.
- **Prop drilling**: Flag components passing more than 5 props through without using them. Suggest context or composition.
- **Business logic in components**: Flag complex business logic (conditionals, transformations, calculations) inline in render/template. Should be extracted to hooks or utility functions.

### 6. Senior Review

Dispatch to the `principal-frontend` subagent with the analysis from the prior steps. Ask it to apply its senior lens — server/client boundary, rendering strategy, import direction, file placement — to the findings. Integrate its top findings into the Report Format below; do not replace the skill's verdict contract.

Invocation:
```
Agent({
  subagent_type: "principal-frontend",
  description: "Architecture senior review",
  prompt: "Review these architectural findings: <summary of boundary, import direction, placement, and component pattern findings from steps 1-5>. Apply senior scrutiny to server/client boundary correctness, rendering strategy choices, import direction, and file placement. Return top architectural risks in severity order."
})
```

## Report Format

```
## Architecture Review

### Server/Client Boundary
- [FAIL] src/components/Dashboard.tsx — uses `useEffect` but missing client directive
- [PASS] src/lib/db.ts — server-only, no client APIs

### Import Direction
- [FAIL] src/lib/format.ts → imports from src/hooks/useAuth.ts (lib cannot import hooks)

### File Placement
- [WARN] src/components/Button.tsx:15 — utility function `cn()` should be in utils/

### DB Access
- [PASS] All database access in server-side files

### Component Patterns
- [WARN] src/components/UserProfile.tsx — 245 lines, consider splitting

### Summary: 2 FAIL, 3 WARN
```
