# Core Workflow Mindset — Stack-Agnostic Engineering Conventions

This document captures the working conventions the `core` workflow skills assume:
how branches, commits, reviews, and plans are handled regardless of language or
stack. It is intended to be imported into a project's `CLAUDE.md` via:

```markdown
# <project> conventions

@plugins/core/MINDSET.md
```

Once imported, these principles become project-level guidance that applies
uniformly to every session. Override or extend any section in your `CLAUDE.md`
when your team's conventions diverge.

---

## Mindset

**Small, reviewable changes beat big-bang drops.** A change a reviewer can hold
in their head ships faster and breaks less. Prefer one focused PR over a sprawling
one, even when the work is related.

**The branch is the unit of work.** Feature work happens on a branch and lands
through a pull request — never directly on the default branch. The PR is where
intent, review, and history converge.

**State your scope, then stay in it.** Know what a change is for before touching
code. Scope creep is the most common way a clean PR turns into an un-reviewable
one. Out-of-scope discoveries become follow-up issues, not surprise commits.

**Verification before assertion.** "Done", "fixed", and "passing" are claims that
require evidence. Run the check, read the output, then say it works.

**History is documentation.** Conventional commit messages and PRs that reference
the issue they close let a future reader reconstruct *why* without archaeology.

---

## Branch & PR discipline

- **Always work on a feature branch + PR.** No carve-out for "small" changes.
- **Branch names carry a type prefix** — `feat/`, `fix/`, `chore/`, `docs/`,
  `refactor/`, `test/`, `perf/`, `build/`, `ci/`, `style/` — optionally followed
  by an issue number, then a short kebab-case slug. Example shapes:
  `feat/123-new-skill`, `fix/broken-hook`, `docs/7-readme`.
- **PRs reference the issue they close** (`Refs #N`, `Closes #N`, `Fixes #N`).
- **Branch from the latest default branch**, not from whatever happened to be
  checked out.

## Commit discipline

- **Conventional Commits**: `<type>(<scope>): <subject>`. Scope names the affected
  component when one applies.
- **One discrete git operation per command.** Do not chain `git add && git commit`
  or `git commit && git push` — each step should be separately inspectable.
- **Never rewrite shared history.** No force-push to a shared branch, no
  `--amend` of a pushed commit, no rebase that someone else has already pulled.
- **Co-authorship is recorded** when a session contributes to a commit.

## What you do NOT do

- You do not commit or push to the default branch directly.
- You do not commit work that the user has not asked to commit — you surface that
  it is ready and let them decide.
- You do not discard uncommitted work (`reset --hard`, `checkout --`, `clean`,
  `stash drop`) without explicit approval — it may be someone else's in-progress
  change.
- You do not expand a change's scope mid-flight without saying so.
- You do not claim a task is complete before running the verification that proves it.
