# Webapp — Web Application Development Skills

Skills for modern web application development. Optimized for Next.js full-stack development (React, TypeScript, Drizzle ORM, Playwright), but patterns are applicable to other web stacks.

## Agents

| Agent | Description |
|-------|-------------|
| `principal-frontend` | Principal-level TypeScript / Node.js / Next.js / React reviewer. Dispatch via `Agent({subagent_type: "principal-frontend"})` from skills needing senior architectural scrutiny — server/client boundary, data-fetching strategy, rendering tradeoffs, accessibility, performance budget. Also invocable directly via `/agents`. |

### How skills use the agent

Dispatch to `principal-frontend` when a review needs senior judgment rather than a line-level checklist:

- `architecture-review` — server/client boundary correctness, import direction, rendering strategy
- `api-review` — type-safety at the boundary, error-handling architecture
- `best-practices` — composition and hook discipline decisions
- `security-review` — XSS sinks and auth posture at scale
- `migration-review` — migration safety and two-phase deploy reasoning

The skill owns the output format; the agent provides the reasoning lens.

## Skills

### Quality Gates
| Skill | Command | Description |
|-------|---------|-------------|
| preflight | `/preflight` | Lint → typecheck → unit tests → e2e → coverage → migration review |
| branch-coverage | `/branch-coverage` | Coverage report scoped to changed files |

### Code Review
| Skill | Command | Description |
|-------|---------|-------------|
| api-review | `/api-review` | Auth, validation, error handling, HTTP conventions |
| architecture-review | `/architecture-review` | Server/client boundary, import direction, file placement |
| best-practices | `/best-practices` | Functional style, composition, hooks, code hygiene |
| dba-review | `/dba-review` | Schema indexes, data types, query antipatterns |
| security-review | `/security-review` | XSS, CSRF, SQL injection, auth bypass |
| docs-review | `/docs-review` | Documentation accuracy, completeness, consistency |
| theme-review | `/theme-review` | Design token usage, semantic colors, dark/light mode |
| migration-review | `/migration-review` | Migration safety, two-phase deploys, data integrity |
| claude-review | `/claude-review` | Full .claude/ configuration audit |

### Testing
| Skill | Command | Description |
|-------|---------|-------------|
| write-tests | `/write-tests` | Generate functional tests following project conventions |
| e2e-spec | `/e2e-spec` | Generate behavioral spec for e2e tests |
| e2e-write | `/e2e-write` | Generate e2e tests from spec or code analysis |
| mutate | `/mutate` | Mutation testing to find test gaps |
| test-matrix | `/test-matrix` | Coverage matrix — which files need tests |
| test-quality | `/test-quality` | Assess test quality, flag anti-patterns |

### Database
| Skill | Command | Description |
|-------|---------|-------------|
| drizzle-sql-migration | `/drizzle-sql-migration` | Drizzle ORM migration guide — schema changes and data fixes |

### Discovery
| Skill | Command | Description |
|-------|---------|-------------|
| suggest | `/suggest` | Recommend libraries, tools, and services to add |

## Setup

Run `/setup` to automatically configure recommended permissions, or manually add to `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm test*)",
      "Bash(npm run lint*)",
      "Bash(npm run format:check*)",
      "Bash(npm run e2e*)",
      "Bash(npx tsc --noEmit*)",
      "Bash(npx knip*)"
    ]
  }
}
```

Operations that modify files (format, lint:fix, drizzle-kit generate/migrate, stryker) are intentionally excluded — you'll be prompted for approval each time.

## Companion Plugins

### Sibling plugins (same repo)

| Plugin | What it adds |
|--------|-------------|
| **core** (recommended) | Commit workflows (`/commit`, `/ship-it`), planning (`/start-work`, `/whats-next`), PR management (`/pr-fix`, `/pr-description`), debugging (`/debug`). Core's commit skill runs webapp preflight checks automatically when this plugin is installed. |
| **infra** | Not typically used alongside webapp, but no conflicts if both are installed. |

### Public plugins

| Plugin | Integration |
|--------|-------------|
| **superpowers** | `test-driven-development` RED-GREEN-REFACTOR for `write-tests` and `e2e-write`. `brainstorming` before feature work. `requesting-code-review` and `receiving-code-review` complement the review skills. |
| **frontend-design** | Production-grade UI generation. Pairs naturally with `theme-review`, `architecture-review`, and `e2e-spec`. |
| **playwright** | Browser automation MCP. Powers `e2e-write` test execution and enables visual testing workflows. |
| **code-simplifier** | Autonomous post-edit refinement — cleans up code after changes, complementing manual review skills. |
