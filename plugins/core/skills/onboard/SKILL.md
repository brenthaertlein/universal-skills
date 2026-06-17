---
name: onboard
description: Guided one-shot install — pick install scope, select plugins (with MINDSET rationale), calibrate risk tolerance into a concrete allowlist + hooks, scaffold or merge CLAUDE.md, and sanity-check the result.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
---

# /onboard

Walk a user through the full install of this marketplace's plugins in one interactive
flow: choose where settings are written, which plugins to enable, how cautious the
allowlist and guard hooks should be, and whether to scaffold a `CLAUDE.md`. Re-runnable —
detects an existing onboard-managed config and merges rather than overwrites.

This skill **only configures what is already installed.** It does not install plugins from
a marketplace — users still pull plugins via the normal Claude Code mechanism. Terminal
only.

## Inputs this skill reads

- **`.claude-plugin/marketplace.json`** — the catalog of available plugins (`name`,
  `description`). Authoritative list to offer in Phase 2.
- **`plugins/<name>/onboard-presets.json`** — per-plugin, per-tier `allow` + `hooks`
  slices. Each plugin owns its own slice. Schema:
  ```json
  {
    "plugin": "<name>",
    "tiers": {
      "cautious":  { "allow": ["Bash(...)", ...], "hooks": [ <PreToolUse hook object>, ... ] },
      "balanced":  { "allow": [...], "hooks": [...] },
      "permissive":{ "allow": [...], "hooks": [...] }
    }
  }
  ```
- **`plugins/<name>/MINDSET.md`** — rationale shown for a plugin during selection (when
  present).

If running outside this repo (i.e. the marketplace files are not on disk), fall back to the
plugin catalog the user has installed via Claude Code and ask which to configure. Never
fabricate a plugin list.

## A note on the plugin hooks floor

Each plugin ships a `hooks/hooks.json` safety floor that is **always active when the plugin
is enabled**, independent of anything this skill writes (e.g. `core` blocks `git push`,
force-delete, reset, restore, clean, amend, stash drop, worktree `--force`, `find -exec`).
The per-tier `hooks` in `onboard-presets.json` are **additional** guards layered into
`settings.json` on top of that floor. So:

- **Permissive** usually contributes no extra hooks — the plugin floor is the safety net.
- **Balanced** adds guards for known-dangerous patterns (`rm -rf`, pipe-to-shell, destroy/delete verbs).
- **Cautious** adds the most guards (recursive `rm`, `sudo`, rebase, force-push, mutating cloud/k8s/db verbs).

Explain this to the user in the summary so they understand the floor is never removed.

## Phase 0: Detect existing config (re-run support)

1. Determine candidate settings files: project `./.claude/settings.json` and user
   `~/.claude/settings.json`.
2. For each that exists, read it and look for an `onboard` marker block:
   ```json
   { "onboard": { "tier": "balanced", "plugins": ["core", "infra"], "version": 1 } }
   ```
   or, lacking a marker, any `permissions.allow` entry that matches a known preset.
3. If a prior onboard config is found, use `AskUserQuestion` — "Existing setup detected.":
   - **Re-tune (merge)** — keep current entries, layer new choices on top, dedupe.
   - **Start fresh** — replace onboard-managed entries (preserve everything else the user
     added by hand).
   - **Cancel** — exit without writing.

   Never silently overwrite. Hand-added entries outside the onboard marker are always preserved.

## Phase 1: Install scope

`AskUserQuestion` — "Where should this configuration be written?":

- **Just this project** — write to `./.claude/settings.json` at the repo root.
- **All my projects** — write to `~/.claude/settings.json`.
- **Both** — write a read-only baseline allowlist to `~/.claude/settings.json` and the
  write/destructive-adjacent entries plus all per-tier hooks and the `onboard` marker to
  `./.claude/settings.json`. Rule for the split: any `allow` entry that is purely a
  read-only probe (`git log/status/diff/show`, `gh * view/list/diff/status`, `find`,
  `grep`, `ls`, `cat`, cloud `describe/get/list`) → global baseline; everything else and
  all hooks → local.

Record the choice; it determines the target file(s) in Phase 3 and 5.

## Phase 2: Plugin selection

1. Read `.claude-plugin/marketplace.json`; list every plugin with its catalog
   `description`.
2. For each plugin, if `plugins/<name>/MINDSET.md` exists, surface a 2–4 line excerpt of
   its opening "Mindset" rationale — not just the name. If a plugin has no `MINDSET.md`
   (e.g. `core`), show its catalog description as the rationale instead.
3. `AskUserQuestion` (multiSelect) — "Which plugins do you want to configure?" with one
   option per plugin. Default-select `core`. Only plugins that have an
   `onboard-presets.json` are eligible for allowlist/hook configuration; if a selected
   plugin lacks one, note it and skip its preset merge (its hooks floor still applies once
   enabled).

## Phase 3: Risk-tolerance calibration

`AskUserQuestion` — "How much should Claude confirm before acting?":

- **Cautious** — minimal allowlist, most operations prompt; the most guard hooks.
- **Balanced** *(default)* — broad read-only allowlist; writes/destructive ops prompt;
  hooks block known-dangerous patterns.
- **Permissive** — broad allowlist for known-safe commands, fewer prompts; hooks block only
  the truly destructive (the plugin floor).

Then build the merged config:

1. For each selected plugin with an `onboard-presets.json`, read the chosen tier's `allow`
   and `hooks`.
2. **Merge `allow`**: union across plugins, dedupe exact duplicates, preserve any pre-existing
   `permissions.allow` entries in the target file.
3. **Merge `hooks`**: collect every tier `hooks` object across selected plugins. Nest them
   under `hooks.PreToolUse` as a single `{ "matcher": "Bash", "hooks": [ ... ] }` entry (or
   merge into an existing Bash matcher entry). Dedupe by the stable `[onboard:<tier>:<id>]`
   tag embedded in each hook's `command` string — never add a hook whose tag already
   exists. This makes re-runs idempotent.
4. **Write the `onboard` marker** `{ "onboard": { "tier", "plugins", "version": 1 } }` into
   the target file so future runs can detect and merge.
5. Apply the Phase 1 scope: single file, or the global/local split for "Both".

Merge semantics: read the target JSON (or `{}` if absent), apply the unions above preserving
all unrelated keys, write back with 2-space indentation. Never drop a key the user added by
hand.

## Phase 4: CLAUDE.md integration

Look for `./CLAUDE.md` at the repo root.

**If absent** — offer to scaffold one. Use `AskUserQuestion` to confirm before writing.
The scaffold includes, tuned by the Phase 3 tier:

- A branch & PR policy section (feature-branch + PR; for cautious, an explicit "never push
  to main" line).
- The Conventional Commits + `Co-Authored-By` trailer convention (model name pulled from the
  runtime, not hardcoded).
- Config keys the selected plugins consume, with tier-appropriate defaults:
  - `start-work.branch-pattern` (default regex; only emit an override if asked)
  - `pr-review.focus-areas` (note: defaults + marker-discovered areas)
  - `ship-it.ci-gate` (`disabled` unless the user says CI exists)
- For each selected plugin that has a `MINDSET.md`, an import line:
  ```markdown
  @plugins/<name>/MINDSET.md
  ```

**If present** — never overwrite. Compute the set of config keys / import lines the selected
plugins want that are missing from the file, show them as a unified diff (additions only),
and use `AskUserQuestion` to let the user accept all / pick selectively / skip. Append
accepted additions; do not reorder or rewrite existing content.

The scaffolded file must parse cleanly through the readers that consume it — `/start-work`
(`start-work.branch-pattern`) and `/pr-review` (`pr-review.focus-areas`) — so keep keys in
the documented shape.

## Phase 5: Sanity checks + summary

1. Validate every settings file written parses as JSON:
   `python3 -m json.tool <file> > /dev/null` (or `jq . <file>`). If a write produced invalid
   JSON, report it and stop — do not leave a broken settings file.
2. Confirm the `onboard` marker is present in the local file.
3. List every file written or modified, with a one-line note each.
4. Report the effective config: number of `allow` entries and number of extra hooks added,
   and remind the user the plugin hooks floor is always active on top.
5. Recommend a first command to try — `/start-work` (begin a work item) or `/whats-next`
   (survey the backlog).

## Safety rules

- Never write a settings file that does not parse — validate before declaring success.
- Never overwrite hand-added settings or `CLAUDE.md` content — merge and dedupe only.
- Never print or display secrets read from any settings file.
- The plugin hooks floor is never removed by this skill; tiers only add guards.
- Always confirm via `AskUserQuestion` before scaffolding `CLAUDE.md` or replacing
  onboard-managed entries.
- If `marketplace.json` and plugin preset files are not on disk, ask the user which
  installed plugins to configure rather than guessing.
