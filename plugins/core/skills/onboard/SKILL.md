---
name: onboard
description: Guided one-shot install — discover installed plugins (or help install new ones), pick install scope, calibrate risk tolerance into a concrete allowlist + hooks, scaffold or merge CLAUDE.md, and sanity-check the result.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
---

# /onboard

Walk a user through configuring this marketplace's plugins in one interactive flow: discover
which plugins are installed (and optionally install more), choose where settings are written,
calibrate how cautious the allowlist and guard hooks should be, and scaffold or merge a
`CLAUDE.md`. Re-runnable — detects an existing onboard-managed config and merges rather than
overwriting.

This skill lives in **core** and is **dynamic**: it never hardcodes core/infra/webapp or any
fixed set. It configures whichever plugins are installed and can offer to install the rest.
It supersedes the old per-plugin `/setup` commands — the risk-tier `balanced` slice in each
plugin's `onboard-presets.json` is the same read-only allowlist `/setup` used to apply.

**Scope: the universal-skills marketplace only.** Consider only plugins belonging to the
`universal-skills` marketplace — the one that ships core and this `/onboard` skill (plugin
keys of the form `"<name>@universal-skills"`). Never read, configure, install, enable, or
mention plugins from any other marketplace (e.g. `claude-plugins-official`). Those are out of
scope for this skill entirely.

## Discovery — how to find plugins and their config

Do **not** assume core/infra/webapp or any fixed set, and **filter everything below to the
universal-skills marketplace** (drop any plugin whose key does not end `@universal-skills`).
Resolve the rest at runtime:

1. **Installed plugins + their on-disk paths** — read
   `~/.claude/plugins/installed_plugins.json`. Its `plugins` object is keyed by
   `"<name>@<marketplace>"`; each value is an array of install records with `installPath`,
   `version`, and `scope` (`user` or `project`, the latter with a `projectPath`). Keep only
   keys ending `@universal-skills`. The `installPath` is the plugin's root on disk — its
   `onboard-presets.json` and `MINDSET.md` (when present) live directly under it.
2. **Enabled state** — read `enabledPlugins` from `~/.claude/settings.json` (user scope) and
   `./.claude/settings.json` (project scope). Keys are `"<name>@<marketplace>": true|false`.
   A universal-skills plugin can be installed but disabled; surface that.
3. **The universal-skills marketplace catalog (to offer installs)** — read
   `~/.claude/plugins/known_marketplaces.json`, find the `universal-skills` entry, and read
   its catalog at `<installLocation>/.claude-plugin/marketplace.json`, whose `plugins` array
   lists every universal-skills plugin (`name`, `description`) whether or not it is installed.
   Ignore all other marketplace entries.
4. **Per-plugin config** — for a plugin at `<installPath>`, read
   `<installPath>/onboard-presets.json` (risk-tier `allow` + `hooks`) and
   `<installPath>/MINDSET.md` (rationale). A plugin may have neither.

**Dev / in-repo fallback**: when `/onboard` is run from inside a marketplace repo itself (the
plugin sources are on disk under `./plugins/<name>/` and a catalog exists at
`./.claude-plugin/marketplace.json`), and `installed_plugins.json` discovery yields nothing
useful for those plugins, resolve presets/MINDSET from `./plugins/<name>/` instead. This keeps
the marketplace author's own dogfooding working.

If none of these sources are readable, ask the user which plugins to configure rather than
guessing. Never fabricate a plugin list.

### `onboard-presets.json` schema

```json
{
  "plugin": "<name>",
  "tiers": {
    "cautious":   { "allow": ["Bash(...)", ...], "hooks": [ <PreToolUse hook object>, ... ] },
    "balanced":   { "allow": [...], "hooks": [...] },
    "permissive": { "allow": [...], "hooks": [...] }
  }
}
```

## A note on the plugin hooks floor

Each plugin ships a `hooks/hooks.json` safety floor that is **always active when the plugin is
enabled**, independent of anything this skill writes (e.g. core blocks `git push`,
force-delete, reset, restore, clean, amend, stash drop, worktree `--force`, `find -exec`). The
per-tier `hooks` in `onboard-presets.json` are **additional** guards layered into
`settings.json` on top of that floor:

- **Permissive** usually contributes no extra hooks — the plugin floor is the safety net.
- **Balanced** adds guards for known-dangerous patterns (`rm -rf`, pipe-to-shell, destroy/delete verbs).
- **Cautious** adds the most guards (recursive `rm`, `sudo`, rebase, force-push, mutating cloud/k8s/db verbs).

Explain this in the summary so the user understands the floor is never removed.

## Phase 0: Detect existing config (re-run support)

1. Candidate settings files: project `./.claude/settings.json` and user `~/.claude/settings.json`.
2. For each that exists, look for an `onboard` marker block:
   `{ "onboard": { "tier": "balanced", "plugins": ["core@universal-skills", ...], "version": 1 } }`,
   or, lacking a marker, any `permissions.allow` entry matching a known preset.
3. If a prior config is found, `AskUserQuestion` — "Existing setup detected.":
   - **Re-tune (merge)** — keep current entries, layer new choices on top, dedupe.
   - **Start fresh** — replace onboard-managed entries; preserve everything the user added by hand.
   - **Cancel** — exit without writing.

   Never silently overwrite. Hand-added entries outside the onboard marker are always preserved.

## Phase 1: Install scope

`AskUserQuestion` — "Where should this configuration be written?":

- **Just this project** — `./.claude/settings.json` at the repo root.
- **All my projects** — `~/.claude/settings.json`.
- **Both** — read-only baseline allowlist to `~/.claude/settings.json`; write/destructive-adjacent
  entries plus all per-tier hooks and the `onboard` marker to `./.claude/settings.json`. Split
  rule: any `allow` entry that is purely a read-only probe (`git log/status/diff/show`,
  `gh * view/list/diff/status`, `find`, `grep`, `ls`, `cat`, cloud `describe/get/list`) →
  global baseline; everything else and all hooks → local.

## Phase 2: Plugin discovery, selection, and optional install

1. Build the **installed set** from `installed_plugins.json` (see Discovery), annotating each
   with enabled/disabled state and whether it exposes an `onboard-presets.json`.
2. Build the **available-but-not-installed set** by diffing the universal-skills marketplace
   catalog against the installed set (universal-skills plugins only).
3. Present installed plugins for selection. For each, surface a 2–4 line excerpt of its
   `MINDSET.md` "Mindset" section as rationale; if it has none, show its catalog `description`
   instead. `AskUserQuestion` (multiSelect) — "Which installed plugins do you want to configure?"
   Default-select the core plugin.
4. If the available-but-not-installed set is non-empty, `AskUserQuestion` — "Install any of
   these too?" listing them with their catalog descriptions. For each one the user picks,
   guide installation (this skill cannot silently install): direct them to the `/plugin` menu,
   or suggest they run the marketplace's install command in-session with the `!` prefix (e.g.
   `! claude plugin install <name>@<marketplace>`). After they confirm, re-read
   `installed_plugins.json` and fold the newly installed plugins into the selection.
5. A selected plugin **without** an `onboard-presets.json` is still valid — note it and skip
   its preset merge (its hooks floor still applies once the plugin is enabled). Also offer to
   flip any selected-but-disabled plugin to enabled in the target `enabledPlugins`.

## Phase 3: Risk-tolerance calibration

`AskUserQuestion` — "How much should Claude confirm before acting?":

- **Cautious** — minimal allowlist, most operations prompt; the most guard hooks.
- **Balanced** *(default)* — broad read-only allowlist; writes/destructive ops prompt;
  hooks block known-dangerous patterns. (This tier equals the old `/setup` allowlist.)
- **Permissive** — broad allowlist for known-safe commands, fewer prompts; hooks block only
  the truly destructive (the plugin floor).

Then build the merged config:

1. For each selected plugin that has an `onboard-presets.json` (resolved from its
   `installPath`, or the in-repo path in the dev fallback), read the chosen tier's `allow`
   and `hooks`.
2. **Merge `allow`**: union across plugins, dedupe exact duplicates, preserve any pre-existing
   `permissions.allow` entries in the target file.
3. **Merge `hooks`**: collect every tier `hooks` object across selected plugins; nest under
   `hooks.PreToolUse` as one `{ "matcher": "Bash", "hooks": [ ... ] }` entry (or merge into an
   existing Bash matcher). Dedupe by the stable `[onboard:<tier>:<id>]` tag in each hook's
   `command` string — never add a hook whose tag already exists. This makes re-runs idempotent.
4. **Write the `onboard` marker** `{ "onboard": { "tier", "plugins": ["<name>@<marketplace>", ...], "version": 1 } }`.
5. Apply the Phase 1 scope (single file, or the global/local split for "Both").

Merge semantics: read the target JSON (or `{}` if absent), apply the unions preserving all
unrelated keys, write back with 2-space indentation. Never drop a key the user added by hand.

## Phase 4: CLAUDE.md integration

Look for `./CLAUDE.md` at the repo root.

**If absent** — offer to scaffold one (confirm via `AskUserQuestion` first). Tuned by the
Phase 3 tier, include:

- Branch & PR policy (feature-branch + PR; for cautious, an explicit "never push to main" line).
- Conventional Commits + `Co-Authored-By` trailer convention (model name from the runtime, not hardcoded).
- Config keys the selected plugins consume, with tier-appropriate defaults — only emit a key
  for a plugin that is actually selected. Common examples: `start-work.branch-pattern`,
  `pr-review.focus-areas`, `ship-it.ci-gate`.
- For each selected plugin that has a `MINDSET.md`, an import line
  `@<path-to>/MINDSET.md` (use the plugin's install path, or `@plugins/<name>/MINDSET.md` in
  the dev/in-repo case).

**If present** — never overwrite. Compute the missing config keys / import lines the selected
plugins want, show them as an additions-only diff, and `AskUserQuestion` to accept all / pick
selectively / skip. Append accepted additions; do not reorder or rewrite existing content.

The scaffolded file must parse through the readers that consume it (`/start-work` →
`start-work.branch-pattern`; `/pr-review` → `pr-review.focus-areas`), so keep keys in the
documented shape.

## Phase 5: Sanity checks + summary

1. Validate every settings file written parses as JSON (`python3 -m json.tool <file>` or
   `jq . <file>`). If a write produced invalid JSON, report and stop — never leave a broken
   settings file.
2. Confirm the `onboard` marker is present in the local file.
3. List every file written or modified, plus any plugins installed/enabled, one line each.
4. Report the effective config: number of `allow` entries and extra hooks added, and remind
   the user the plugin hooks floor is always active on top.
5. Recommend a first command — `/start-work` (begin a work item) or `/whats-next` (survey the backlog).

## Safety rules

- Never write a settings file that does not parse — validate before declaring success.
- Never overwrite hand-added settings or `CLAUDE.md` content — merge and dedupe only.
- Never silently install or enable a plugin — always confirm, and let the user run the install.
- Never print or display secrets read from any settings file.
- The plugin hooks floor is never removed by this skill; tiers only add guards.
- Always confirm via `AskUserQuestion` before scaffolding `CLAUDE.md` or replacing
  onboard-managed entries.
- If plugin-discovery sources are unreadable, ask which plugins to configure rather than guessing.
