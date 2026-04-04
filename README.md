# Claude Code Plugins

Battle-tested Claude Code skills extracted from real projects, generalized for any codebase.

## Plugins

### `core` — Universal Workflow

Stack-agnostic skills for commit workflows, project planning, debugging, PR management, and documentation. Works with any language or framework.

**13 skills:** commit, ship-it, start-work, whats-next, project-status, pr-description, skills-review, debug, pr-fix, document, improve-issues, cleanup, checkout

### `infra` — Infrastructure & DevOps

Skills for infrastructure-as-code projects using Terraform, Ansible, Kubernetes, Helm, and Docker Compose.

**3 skills:** preflight, security-audit, suggest

### `webapp` — Web Application Development

Skills for modern web app development, optimized for Next.js full-stack (React, TypeScript, Drizzle, Playwright). API review, architecture review, testing, coverage analysis, migration safety, and design tokens.

**17 skills:** preflight, api-review, architecture-review, best-practices, dba-review, security-review, docs-review, theme-review, migration-review, claude-review, branch-coverage, write-tests, e2e-spec, e2e-write, mutate, test-matrix, test-quality, drizzle-sql-migration, suggest

## Installation

```bash
claude plugins install <plugin-name>
```

## Recommended Combinations

Install **core** as your base, then add a domain plugin and public companion plugins:

| Stack | Install |
|-------|---------|
| Web app | core + webapp + superpowers + frontend-design + playwright |
| Infrastructure | core + infra + superpowers |
| Any project | core + superpowers + code-simplifier |

## Companion Plugins

These plugins integrate with public plugins from the Claude Code marketplace:

| Plugin | What it adds | Works with |
|--------|-------------|------------|
| **superpowers** | Process discipline — brainstorming, TDD, systematic debugging, verification, code review | core, infra, webapp |
| **frontend-design** | Production-grade UI generation | webapp |
| **playwright** | Browser automation MCP for e2e test execution | webapp |
| **code-simplifier** | Autonomous post-edit code refinement | core, infra, webapp |

## Origin

These skills were extracted from production projects and refined through hundreds of real development sessions, iterated based on actual failures and feedback.


## License

MIT
