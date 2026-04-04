---
name: checkout
description: Create a worktree for an existing branch — fetches, sets up environment, installs deps, and reports the path.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, AskUserQuestion
---

# Checkout -- Resume work on an existing branch

Create a git worktree for an existing remote branch, set up the environment, install dependencies, and start working.

## How to use

```
/checkout feat/42-add-search
/checkout fix/login-redirect
```

Accepts a branch name. If no argument is provided, ask the user with `AskUserQuestion`: "Which branch should I check out?"

## Execution

### 1. Resolve the branch name

- If an argument was provided, use it as the branch name
- If no argument, prompt with `AskUserQuestion`

### 2. Fetch the branch

```bash
git fetch origin <branch-name>
```

If the branch does not exist on the remote, report the error and suggest similar branches:

```bash
git branch -r | grep -i "<partial-name>"
```

Ask the user to try again.

### 3. Create the worktree

```bash
# Sanitize branch name for directory (replace slashes with dashes)
WORKTREE_DIR=".worktrees/$(echo '<branch-name>' | tr '/' '-')"

# Create worktree tracking the remote branch
git worktree add "$WORKTREE_DIR" "origin/<branch-name>"

# Fix detached HEAD by creating/checking out local tracking branch
cd "$WORKTREE_DIR"
git checkout -B "<branch-name>" --track "origin/<branch-name>"
```

If a worktree already exists for this branch, report it and cd into the existing worktree instead.

### 4. Copy environment files

Copy environment files from the project root into the worktree if they exist. Check for common patterns:

```bash
# Copy env files if they exist in the project root
for envfile in .env .env.local .env.test .env.development; do
  if [ -f "../../$envfile" ]; then
    cp "../../$envfile" "./$envfile"
  fi
done
```

### 5. Install dependencies

Auto-detect the project's package manager and install dependencies:

| Indicator file | Install command |
|---------------|-----------------|
| `package-lock.json` | `npm install` |
| `yarn.lock` | `yarn install` |
| `pnpm-lock.yaml` | `pnpm install` |
| `bun.lockb` | `bun install` |
| `requirements.txt` | `pip install -r requirements.txt` |
| `Pipfile.lock` | `pipenv install` |
| `poetry.lock` | `poetry install` |
| `Cargo.toml` | `cargo build` |
| `go.mod` | `go mod download` |
| `Gemfile.lock` | `bundle install` |
| `composer.lock` | `composer install` |

If multiple indicators are present (e.g. a project with both `package.json` and `requirements.txt`), run all applicable install commands.

Check CLAUDE.md for any project-specific setup commands that should run after dependency installation.

### 6. cd into the worktree

**This is mandatory.** After setup succeeds, `cd` into the worktree directory so all subsequent work happens there:

```bash
cd "$WORKTREE_DIR"
```

### 7. Report

On success, tell the user:
- The worktree path
- The branch name
- That you are now working in the worktree directory
- Remind them to start their dev server in the worktree directory if needed

## Safety Rules

- **Never switch branches in the main working tree** -- worktrees only
- **Never delete existing worktrees** -- if one exists for the branch, report it and use it
- **Never push or commit** -- this skill only sets up the workspace
