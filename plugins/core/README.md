# Core — Universal Workflow Skills

Stack-agnostic workflow skills for Claude Code. Works with any language, framework, or project type.

## Skills

### Workflow
| Skill | Command | Description |
|-------|---------|-------------|
| commit | `/commit` | Preflight checks + commit. Does not push. |
| ship-it | `/ship-it` | Full pipeline: commit → push → PR → follow-ups |
| checkout | `/checkout <branch>` | Create a worktree for an existing branch |
| cleanup | `/cleanup` | Remove worktrees whose PR has been merged or closed |
| debug | `/debug <description>` | Senior-engineer debugging: evidence first, fix last |
| pr-fix | `/pr-fix` | Triage PR review comments, classify, and fix |

### Planning
| Skill | Command | Description |
|-------|---------|-------------|
| start-work | `/start-work <issue>` | Research → plan → implement from an issue or doc |
| whats-next | `/whats-next` | Recommend your next task based on issues and history |
| project-status | `/project-status` | Dashboard of PRs, issues, and branches |

### Documentation
| Skill | Command | Description |
|-------|---------|-------------|
| pr-description | `/pr-description` | Generate structured PR description from branch diff |
| document | `/document [issue/feature]` | Create/update feature and issue docs |
| improve-issues | `/improve-issues` | Enrich GitHub issues with context and labels |

### Meta
| Skill | Command | Description |
|-------|---------|-------------|
| skills-review | `/skills-review` | Audit skills for overlap, gaps, and consistency |

## Setup

Run `/setup` to automatically configure recommended permissions, or manually add to `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git log*)",
      "Bash(git status*)",
      "Bash(git diff*)",
      "Bash(git show*)",
      "Bash(git fetch*)",
      "Bash(git branch --show-current*)",
      "Bash(git branch -a*)",
      "Bash(git branch --list*)",
      "Bash(git stash list*)",
      "Bash(git stash show*)",
      "Bash(git worktree list*)",
      "Bash(gh pr view*)",
      "Bash(gh pr list*)",
      "Bash(gh pr checks*)",
      "Bash(gh pr diff*)",
      "Bash(gh pr status*)",
      "Bash(gh run view*)",
      "Bash(gh run list*)",
      "Bash(gh issue list*)",
      "Bash(gh issue view*)",
      "Bash(gh repo view*)",
      "Bash(gh api repos/*/pulls/*/reviews*)",
      "Bash(gh search issues*)",
      "Bash(gh search prs*)",
      "Bash(find *)",
      "Bash(grep *)",
      "Write(.plans/*)",
      "Edit(.plans/*)"
    ]
  }
}
```

Operations that modify state (commit, push, merge, PR create, issue edit, branch create) are intentionally excluded — you'll be prompted for approval each time.

## Development Workflow

Core skills cover the full feature/bugfix loop:

```
start-work  →  ship-it  →  pr-fix  →  ship-it
```

`commit` is used within a PR review cycle to batch incremental fixes without triggering CI on every change.

When **superpowers** and/or **feature-dev** are installed, `start-work` offers richer paths but the lightweight path above always remains available:

```
# Lightweight (standalone)
start-work → [implement] → ship-it → pr-fix → ship-it

# With feature-dev
start-work → feature-dev (explore + architecture) → [implement] → ship-it → pr-fix → ship-it

# With superpowers full pipeline
start-work → brainstorming → writing-plans → subagent-driven-development → ship-it → pr-fix → ship-it
```

Supporting skills (`scope-statement-check`, `comment-discipline`, `error-handling-preflight`) fire automatically inside `start-work`, `commit`, and `pr-fix` when installed — they do not need to be invoked directly.

## Companion Plugins

### Sibling plugins (same repo)

| Plugin | What it adds |
|--------|-------------|
| **infra** | IaC preflight checks (Terraform, Ansible, K8s, Helm, Docker Compose), security scanning, infra service recommendations |
| **webapp** | Web app preflight (lint, typecheck, tests), code review skills, testing tools, library recommendations |

Core works standalone, but `/commit` and `/ship-it` run richer preflight checks when a domain plugin is installed.

### Public plugins

| Plugin | Integration |
|--------|-------------|
| **superpowers** | `start-work` offers brainstorming + writing-plans + subagent-driven-development path. `commit` gains verification-before-completion discipline. `debug` gains systematic-debugging methodology. `ship-it` dispatches requesting-code-review and notes finishing-a-development-branch for pipeline branches. |
| **feature-dev** | `start-work` offers parallel agent codebase exploration and architecture design as an alternative to the Quick start path. |
| **code-simplifier** | Autonomous post-edit refinement — runs after code changes to improve clarity and consistency. Complements the manual review skills. |
