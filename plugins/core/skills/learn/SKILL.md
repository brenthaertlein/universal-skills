---
name: learn
description: Review project memory and promote durable lessons into CLAUDE.md / settings (with confirmation); file a GitHub issue when a lesson is a defect in one of this repo's own skills.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, AskUserQuestion, Skill
argument-hint: [blank — fully interactive]
---

# Learn

Promote durable lessons out of per-project auto-memory into the config that actually changes behavior — project or user `CLAUDE.md`, and `settings.json` / `settings.local.json` via the `update-config` skill — after you review and confirm every change.

Memory is a staging area for observations Claude accumulates while working. `CLAUDE.md` and settings are the authoritative, persistent config. `/learn` is the bridge: it reads what's been learned, proposes where each lesson belongs, and writes nothing without explicit approval. When a lesson is really a defect in a skill that lives in *this* repo, it offers to file a GitHub issue against `origin` instead of burying the fix in local config.

## How to use

- `/learn` — fully interactive. Reads this project's memory and walks through promotable lessons.

There are no arguments — the skill always reads the current project's memory and prompts for selections.

## Workflow

### 1. Locate and load memory

Resolve this project's memory directory from the working directory (the auto-memory path mirrors the cwd with `/` replaced by `-`):

```bash
echo "$HOME/.claude/projects/$(pwd | sed 's#/#-#g')/memory"
```

Read `MEMORY.md` (the index) and every `*.md` memory file in that directory. For each file parse the frontmatter (`name`, `description`, `metadata.type`) and keep the body.

If the directory is missing or empty, report that there's nothing to learn from yet and stop.

### 2. Present the menu

Show a table of memories grouped by `type`:

| Memory | Type | Summary | Proposed destination |
|--------|------|---------|---------------------|

The **Proposed destination** comes from the routing rules in step 3 — show your suggested home for each so the user can see the plan at a glance.

Then ask via `AskUserQuestion` (multiSelect) which memories to learn from. Offer "all", a subset, or cancel. Only the selected memories proceed.

### 3. Classify and route each selected memory

Map each memory to a destination by its `type` and content:

- **`type: project`** → project `./CLAUDE.md`.
- **`type: user`** (who the user is, durable cross-project preferences) → user `~/.claude/CLAUDE.md`.
- **`type: feedback`** — decide by what the lesson is:
  - General working preference that holds across projects → user `~/.claude/CLAUDE.md`.
  - A rule specific to this project → project `./CLAUDE.md`.
  - An **automatable behavior** — "whenever / before / after X, do Y", a permission to grant, or an env var — → **settings**, applied via the `update-config` skill (project `settings.json`, or `settings.local.json` / user settings when it's personal).
- **`type: reference`** → a "See also" entry in project `./CLAUDE.md`, or skip if it isn't worth persisting.

#### Skill-defect detection (GitHub issue path)

A feedback memory sometimes describes a genuine defect or gap in a *skill itself*, not a personal preference. Offer to file a GitHub issue **only when all of these hold**:

- The lesson names or clearly concerns a specific skill, **and that skill's `SKILL.md` exists in the current repo's working tree** (so `origin` is a repo we own).
- The problem is unambiguous — a concrete behavior that's wrong or missing, not a matter of taste.
- It is **not** a personal preference. Preferences belong in `CLAUDE.md`/settings; defects belong upstream.

If the named skill is **not** in this working tree (a third-party / installed plugin skill), keep the lesson local — never file issues against remotes we don't own. We are not responsible for improving other people's plugins, and unsolicited issues are spam.

When ambiguous between "preference" and "defect", treat it as a preference, route it to local config, and ask.

### 4. Propose and confirm — required gate

For each selected memory, present the concrete proposed change before touching anything:

- **Target** — exact file (and section) or `update-config` / GitHub issue.
- **Change** — the literal text to add or modify, shown diff-style.
- **Why** — the lesson it encodes, traced back to the memory.

Then ask via `AskUserQuestion`:

> Apply this change / Edit the wording / Route elsewhere / Skip

Nothing is written without an explicit "Apply" (or an edited variant the user approves). Silence is never approval.

### 5. Apply the approved changes

- **`CLAUDE.md`** — use `Edit`/`Write` to insert under the right section, creating the section or the file if it doesn't exist yet. Keep the existing voice and structure of the file.
- **Settings / hooks / permissions / env** — invoke the `update-config` skill with the specific change. Do **not** hand-edit `settings.json` / `settings.local.json`; `update-config` owns hook and permission syntax.
- **GitHub issue** — draft a title and body, show a preview, confirm via `AskUserQuestion`, then create it against `origin`:

  ```bash
  gh issue create --title "<title>" --body "$(cat <<'EOF'
  <body>
  EOF
  )"
  ```

  One `gh` call per Bash invocation. Reference the source lesson in the body so the issue stands on its own.

### 6. Reconcile the source memory

After a lesson lands durably, the original memory is redundant. Ask per memory via `AskUserQuestion`:

> Prune (delete the file and its `MEMORY.md` line) / Keep / Annotate as promoted

Apply the choice. Pruning keeps memory from drifting out of sync with the config that now owns the fact.

### 7. Summary

Report what changed: files touched, settings applied via `update-config`, issues filed (with URLs), and memories pruned / kept / annotated.

## Rules

- **Confirm before every write.** Steps 4 and 6 both require an explicit choice. Silence is never approval, and no file is edited speculatively.
- **`/learn` never commits.** It edits the working tree and files issues; committing stays with `/commit` // `/ship-it`. If you're on the default branch and about to edit a tracked `CLAUDE.md`, warn the user and suggest branching first (e.g. via `/start-work`).
- **All settings changes go through `update-config`.** Never hand-edit `settings.json` / `settings.local.json` from this skill.
- **GitHub issues only against `origin`, only for skills in this working tree.** A lesson about a third-party plugin skill stays in local config — no upstreaming to remotes we don't own.
- **One git / `gh` command per Bash call.** Never chain; separate calls keep each step inspectable and match the per-command allowlist.
- **Everything derived dynamically.** Memory path, repo origin, and skill locations are resolved at runtime — no hardcoded project or org names.
- **Preference vs defect.** Personal preference → local config. Unambiguous skill defect in this repo → GitHub issue. When unsure, treat as preference and ask.
