# Universal Agent Skills

Battle-tested agent plugins (Claude Code, Cursor, Copilot CLI) extracted from real projects, generalized for any codebase. Each plugin ships skills, agents, commands, hooks, and shared helper scripts — wired to work together out of the box.

The **universal-skills** marketplace is declared for Cursor at [`.cursor-plugin/marketplace.json`](.cursor-plugin/marketplace.json) ([Cursor multi-plugin repos](https://cursor.com/docs/reference/plugins)) and for Claude Code / Copilot at [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

## Plugins

### `core` — Universal Workflow

Stack-agnostic skills for commit workflows, project planning, debugging, PR management, and documentation. Works with any language or framework.

**13 skills:** commit, ship-it, start-work, whats-next, project-status, pr-description, skills-review, debug, pr-fix, document, improve-issues, cleanup, checkout

### `infra` — Enterprise Infrastructure & DevOps

For sysadmins, DevOps engineers, and SREs operating across AWS, GCP, Kubernetes, and baremetal/on-prem. Covers IaC validation, drift / cost / vulnerability triage, cloud IAM and Well-Architected reviews, postmortems and runbooks, and baremetal hardening. All skills are **read-only** — mutating operations always require approval.

- **23 skills** grouped as:
  - **Foundations:** `preflight`, `security-audit`, `suggest`, `infra-inventory`
  - **Cross-cutting:** `review-drift`, `review-costs`, `triage-vulnerabilities`, `draft-postmortem`, `draft-runbook`, `review-observability`, `assess-change-risk`, `review-disaster-recovery`
  - **AWS:** `review-aws-iam`, `review-aws-well-architected`, `review-aws-tagging`, `triage-aws-security-findings`
  - **GCP:** `review-gcp-iam`, `triage-gcp-recommender`, `review-gke`
  - **Kubernetes:** `review-kubernetes-rbac`
  - **Baremetal:** `review-linux-hardening`, `review-systemd-units`, `review-ansible-playbooks`, `triage-hardware-health`
- **1 agent:** `principal-sre` — principal-level sysadmin / DevOps / SRE reviewer persona dispatched by 5 skills (`draft-postmortem`, `assess-change-risk`, `review-disaster-recovery`, `review-observability`, `draft-runbook`) when senior production judgment is needed.
- **Helper scripts:** `detect-iac-scope.sh`, `cloud-auth-check.sh` — shared IaC detection and cloud-auth probing used by 12 skills.
- **Hooks:** 4 `PreToolUse` safeguards nudging `/preflight`, `/security-audit`, `/assess-change-risk`, `/review-drift` before mutating `terraform`, `kubectl`, `helm`, or `ansible-playbook` operations.
- **[`MINDSET.md`](plugins/infra/MINDSET.md):** import via `@plugins/infra/MINDSET.md` into a project `CLAUDE.md` to adopt enterprise infra conventions (change safety, config-as-code, secrets discipline, observability gates, production maxims).

### `webapp` — Web Application Development

For modern Next.js / TypeScript / React full-stack development (Drizzle ORM, Playwright, Vitest). API review, architecture review, testing, coverage analysis, migration safety, and design tokens.

- **19 skills:** preflight, api-review, architecture-review, best-practices, dba-review, security-review, docs-review, theme-review, migration-review, claude-review, branch-coverage, write-tests, e2e-spec, e2e-write, mutate, test-matrix, test-quality, drizzle-sql-migration, suggest
- **1 agent:** `principal-frontend` — principal-level TypeScript / Next.js / React reviewer persona dispatched by 5 skills (`architecture-review`, `api-review`, `best-practices`, `security-review`, `migration-review`) when the decision is architectural rather than line-level.
- **[`MINDSET.md`](plugins/webapp/MINDSET.md):** import via `@plugins/webapp/MINDSET.md` into a project `CLAUDE.md` to adopt type-discipline, server/client boundary, testing, accessibility, and performance conventions.

## Installation

### Claude Code

```bash
claude plugins install <plugin-name>
```

Each plugin ships a `/setup` command that adds the recommended read-only tool permissions to `.claude/settings.json`. Mutating operations are intentionally excluded and will always prompt for approval.

### Cursor (IDE & CLI)

If you **only use Cursor** (not Claude Code or Copilot CLI), rely on **`.cursor-plugin/`** at the repository root: [`marketplace.json`](.cursor-plugin/marketplace.json) lists the **universal-skills** marketplace, and each of `plugins/core`, `plugins/infra`, and `plugins/webapp` has its own **`plugin.json`**. See the [Plugins reference → Multi-plugin repositories](https://cursor.com/docs/reference/plugins).

Install plugins from Cursor’s marketplace UI — the same installs apply to **[desktop, web, and the `agent` CLI](https://cursor.com/help/customization/plugins)** ([Cursor CLI](https://cursor.com/docs/cli.md)) with no separate “CLI-only” plugin installer.

**1. Cursor app (public marketplace)**

When **universal-skills** (or individual plugins from this repo) are available on [cursor.com/marketplace](https://cursor.com/marketplace), open the Plugins / Marketplace experience in Cursor, find **core**, **infra**, or **webapp**, and install with **project** or **user** scope. To publish or update a listing, use [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish) and the [submission checklist](https://cursor.com/docs/reference/plugins) (includes multi-plugin repos with `.cursor-plugin/marketplace.json` at the repo root).

**2. Team / Enterprise (import this GitHub repo)**

On Teams or Enterprise, import this repository as a **[team marketplace](https://cursor.com/docs/plugins)**: **Dashboard → Settings → Plugins → Team Marketplaces → Import** → paste **this repo’s HTTPS or SSH clone URL**. Confirm the marketplace name **universal-skills** and the three plugins (`core`, `infra`, `webapp`) parse correctly, then assign access as needed.

**3. Local checkout (symlink)**

To test against a clone without publishing, symlink each plugin into Cursor’s local plugin directory ([Test plugins locally](https://cursor.com/docs/plugins)):

```bash
REPO=/absolute/path/to/this/repo
mkdir -p ~/.cursor/plugins/local
ln -sfn "$REPO/plugins/core"   ~/.cursor/plugins/local/core
ln -sfn "$REPO/plugins/infra"  ~/.cursor/plugins/local/infra
ln -sfn "$REPO/plugins/webapp" ~/.cursor/plugins/local/webapp
```

Restart Cursor or run **Developer: Reload Window**.

**Commands / `/setup`:** Slash commands reference paths like `.claude/settings.json`; on Cursor-only workflows you configure tool permissions under **Cursor Settings** as usual — see [Plugins](https://cursor.com/docs/plugins.md) and CLI [configuration](https://cursor.com/docs/cli/reference/configuration.md) if you rely on **`agent`**.

### GitHub Copilot CLI

**1. Register this marketplace**

```bash
copilot plugin marketplace add <owner>/<repo>
```

> **SSH auth users:** the `<owner>/<repo>` shorthand clones over HTTPS, which no longer accepts passwords — PAT/credential-helper mismatches appear as "Invalid username or token." Pass an explicit SSH URL instead:
>
> ```bash
> # Remove any failed partial clone first
> rm -rf ~/Library/Caches/copilot/marketplaces/<owner>-<repo>
>
> copilot plugin marketplace add ssh://git@github.com/<owner>/<repo>.git
> ```
>
> Or force all GitHub clones to use SSH globally (then the shorthand works again):
>
> ```bash
> git config --global url."ssh://git@github.com/".insteadOf "https://github.com/"
> ```
>
> Verify SSH access first: `ssh -T git@github.com`

**2. Browse available plugins**

```bash
copilot plugin marketplace list            # confirm the marketplace name
copilot plugin marketplace browse <name>   # list plugins in this marketplace
```

**3. Install a plugin**

```bash
copilot plugin install <plugin-name>@<marketplace-name>
```

**4. Manage**

```bash
copilot plugin list
copilot plugin update <plugin-name>
copilot plugin uninstall <plugin-name>
```

## Adopting the MINDSET files

To apply a plugin's enterprise conventions to a project, import the MINDSET file into the project's `CLAUDE.md`:

```markdown
# <project> conventions

@plugins/infra/MINDSET.md
@plugins/webapp/MINDSET.md
```

These distill principal-engineer conventions — change safety, testing discipline, server/client boundary, secrets handling, observability gates — from real production codebases, with no project-specific leakage. Override individual sections in your own `CLAUDE.md` where your org diverges.

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
