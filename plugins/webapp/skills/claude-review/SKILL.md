---
name: claude-review
description: "Holistic audit of .claude/ configuration, skills inventory, CLAUDE.md quality, settings, hooks, and memory."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Claude Configuration Review

Audit the project's Claude Code configuration for completeness, correctness, and coherence.

## Invocation

`/claude-review` — reviews the entire `.claude/` directory and `CLAUDE.md`.

## Checks

### 1. Skills Inventory

Scan for all SKILL.md files in the project (including plugin skills).

- List each skill with: name, description, invocability, allowed tools.
- Flag skills with missing or malformed frontmatter.
- Flag skills with no description.
- Flag duplicate skill names across directories.
- Check that all skills referenced in CLAUDE.md actually exist.

### 2. CLAUDE.md Review

Evaluate the project's CLAUDE.md as an LLM context document:

- **Completeness**: Does it cover project structure, key commands, conventions, and architecture?
- **Accuracy**: Do referenced files, commands, and paths actually exist?
- **Conciseness**: Is it focused and free of redundant information?
- **Structure**: Is it well-organized with clear headers and sections?
- **Actionability**: Does it contain specific, actionable guidance (not vague principles)?

### 3. Settings & Hooks Review

Review `.claude/settings.json` (or equivalent):

- List all configured hooks (pre-commit, post-commit, custom).
- Verify hook commands are valid and executable.
- Flag hooks that reference missing scripts or tools.
- Check for conflicting settings.

### 4. Memory Review (Read-Only)

If a memory file exists (`.claude/memory.md`, `.claude/memory.json`, or equivalent):

- Read and summarize key stored preferences and decisions.
- Do NOT modify memory. This is read-only.
- Flag contradictions between memory and CLAUDE.md.

### 5. Holistic Coherence

Cross-check all configuration for consistency:

- Skills should align with project type (e.g., no database skills for a static site).
- CLAUDE.md guidance should match configured hooks and settings.
- Tool restrictions in skills should make sense (e.g., review skills shouldn't need Write).
- Flag configuration that appears copied from another project without adaptation.

## Report Format

```
## Claude Configuration Audit

### Skills: 12 found
- preflight (user-invocable, 6 tools) ✓
- api-review (user-invocable, 3 tools) ✓
- [WARN] write-tests — missing description in frontmatter

### CLAUDE.md Quality: GOOD
- [WARN] References `npm run test:integration` but no such script exists
- [PASS] Well-structured, complete project overview

### Settings: OK
- 2 hooks configured, both valid

### Memory: 3 entries
- [PASS] No contradictions with CLAUDE.md

### Coherence: GOOD
- [WARN] dba-review skill present but no database configuration detected
```
