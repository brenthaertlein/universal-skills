# CLAUDE.md — universal-skills

Guidance for any Claude Code session working on this repo. Applies on top of any user-level `~/.claude/CLAUDE.md`.

## About this repo

`universal-skills` is a Claude Code plugin marketplace. Tracked artifacts are **plugin files only**: skills, commands, hooks, plugin manifests, READMEs, and the marketplace catalog. Process scaffolding (design specs, brainstorming output, planning docs) does **not** belong in git history — see "What doesn't get committed" below.

Three plugins live here:

| Plugin | Scope |
|---|---|
| `core` | Stack-agnostic workflow skills — `/start-work`, `/commit`, `/ship-it`, `/pr-fix`, `/pr-review`, `/checkout`, `/cleanup`, `/debug`, `/document`, `/improve-issues`, `/pr-description`, `/project-status`, `/skills-review`, `/whats-next`, plus supporting skills |
| `infra` | Infrastructure-focused reviews and operations — IaC, cloud (AWS / GCP), Kubernetes, Linux, Ansible, observability, DR, costs |
| `webapp` | Web-application reviews and testing — API, DB, migrations, security, architecture, theming, a11y, e2e, mutation testing |

## Branch & PR policy

- **Always work on a feature branch + PR.** Never commit or push directly to `main`. This rule has no carve-out for "small" changes.
- **Branch naming follows the `core/start-work` default regex:** `^(feat|fix|chore|docs|refactor|test|perf|build|ci|style)/(?:[0-9]+-)?[a-z0-9][a-z0-9-]*$`. Example shapes: `feat/123-new-skill`, `fix/broken-hook`, `docs/7-claude-md`, `refactor/cleanup-rewrite`.
- **PRs reference the issue they close.** Use `Refs #N`, `Closes #N`, or `Fixes #N` in the PR description.
- **`/ship-it` is the canonical publishing path.** It runs preflight, commits via `/commit`, pushes, and opens the PR. Do not assemble those steps ad-hoc.

## Commit conventions

- **Conventional Commits**: `<type>(<scope>): <subject>` (`feat(core):`, `docs:`, `fix(infra):`, etc.). Scope matches the affected plugin when applicable.
- **HEREDOC for all multi-line commit messages and PR bodies** so the runtime preserves formatting.
- **Co-Authored-By trailer** is required on every commit and uses the current Claude model name from the runtime environment, e.g.:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
  Do not hardcode a stale version.
- **Never chain git commands** in one shell invocation. `git commit && git push`, `git add && git commit`, `git commit && git log` — all forbidden. One discrete git operation per command, both for human inspect-ability between steps and because chained command strings break Claude Code's per-command allowlist patterns.

## Per-task artifact paths

Skill-managed per-task state is **never committed** — it is all gitignored.

| Path | Owner | Purpose |
|---|---|---|
| `.worktrees/<branch>/` | `/checkout`, `/cleanup` | Per-branch worktrees |
| `.scope/<branch>.md` | `/scope-statement-check` | Per-branch scope contracts |

Keep `.worktrees/` and `.scope/` at the repo root rather than under `.claude/` — writes under `.claude/` can trigger a settings-permission prompt that interrupts edit mode.

Plans are also never committed. `/start-work` plans and Claude's native `/plan` docs may live under `.plans/` or `.claude/plans/` depending on which produced them; either way they stay out of git history.

## Skill configuration

Configuration keys consumed by skills in this repo. Defaults are baked into each skill; the values below are this repo's project-level choices.

### `pr-review.focus-areas` (`/pr-review`)

Use defaults. The four baked-in defaults (Security / Architecture / Tests / Docs) plus every focus area discovered via the `[pr-review-focus-area: <Name>]` marker on installed skills cover this repo's needs. The marker is documented in `plugins/core/skills/pr-review/SKILL.md`.

### `ship-it.ci-gate` (`/ship-it`)

```yaml
ship-it.ci-gate: disabled
```

This repo currently has no required CI checks configured. Skip the gate entirely. Re-enable to `enabled` once CI lands.

### `start-work.branch-pattern` (`/start-work`)

Use the default regex (specified under "Branch & PR policy" above). No override needed.

## What doesn't get committed

Hard rules — apply regardless of which skill is active:

- **No design specs, brainstorming output, or writing-plans output in tracked history.** Paths under `docs/superpowers/` are gitignored as a backstop, but the rule applies even if `.gitignore` is missing or modified. Discuss designs in chat; keep throwaway plans out of git.
- **Everything stands on its own.** Skills, commands, examples, and identifiers must be general-purpose. No organization or project names, and no stack-specific identifiers that don't belong in a general-purpose skill. Describe each artifact in its own terms.
- **No scratch files in commits.** Tree dumps, screenshots, throwaway logs — leave them out of the working tree or gitignore them; never stage them as part of a feature.

## Skill-author guidance

For anyone adding a new skill that wants to contribute to `/pr-review`:

1. Pick a stack-agnostic display name (avoid leaking your stack into the marketplace).
2. Prefix the skill's `description:` value with `[pr-review-focus-area: <Display Name>] ` (note the trailing space before the regular description).
3. Choose a display name that either complements the four baked-in defaults (Security / Architecture / Tests / Docs) or stands on its own. Same display name as a default explicitly overrides the senior-engineering fallback for that name; distinct name surfaces as a separate focus area.

For anyone adding any skill at all:

- Frontmatter uses `user-invocable: true` (hyphenated), `disable-model-invocation` as appropriate, and `allowed-tools` listing exactly what the skill needs.
- Read-only review skills must not include `Edit`, `Write`, or autofix-style tools in `allowed-tools` and should declare read-only invariants in their prompt.
- Use `AskUserQuestion` for any branching decision the user should make — never assume silence is approval.

## See also

- `plugins/core/README.md` — full command reference for `core`.
- `plugins/infra/README.md` — `infra` plugin overview.
- `plugins/webapp/README.md` — `webapp` plugin overview.
- `plugins/core/commands/setup.md` — recommended allowlist for `.claude/settings.json`.
