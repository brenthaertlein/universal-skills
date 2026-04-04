---
name: skills-review
description: Audit all Claude skills for overlap, inconsistencies, gaps, and alignment with CLAUDE.md.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob
---

# /skills-review

Audit all Claude skills in this project for overlap, inconsistencies, gaps, and alignment with project instructions.

## Phase 1: Inventory

Build a complete inventory of all skills.

1. Glob for skill files:
   - `.claude/skills/*/SKILL.md` (project skills)
   - Scan for any installed plugin skills referenced in `.claude/settings.json` or `.claude/plugins/`
2. Read each skill file and extract:
   - name
   - description
   - user-invocable (true/false)
   - disable-model-invocation (true/false)
   - allowed-tools list
   - Section headings (phases, steps)
   - What the skill does (validates, generates, modifies, reports)
3. Present summary table:

| Skill | Source | User-invocable | Auto-trigger | Tools | Purpose |
|-------|--------|---------------|-------------|-------|---------|

Source column: "project", "plugin: <name>", etc.

## Phase 2: Overlap & Duplication

Cross-compare skills for overlapping concerns. Common overlaps to evaluate:

- **Validation/check skills**: Do multiple skills run the same checks? (e.g., a preflight skill and a commit skill that both run linting)
- **Work discovery**: Multiple skills that scan issues or docs for work items
- **PR/shipping pipeline**: Skills that overlap in the commit-push-PR workflow
- **Planning vs execution**: Skills that both research and plan work items
- **Review skills**: Multiple review skills with overlapping checklists

Classify each overlap:

- **Complementary** (OK) — Skills address different phases or angles, work well together
- **Redundant** (consolidate) — Significant duplication, recommend merging
- **Conflicting** (must fix) — Contradictory instructions or overlapping outputs

| Check area | Skills involved | Classification | Notes |
|-----------|----------------|---------------|-------|

## Phase 3: Inconsistency Detection

### 3a. Severity taxonomy

If skills report findings (errors, warnings, etc.), do they use consistent severity levels? Check for:
- Inconsistent naming (error vs blocker, warning vs caution, advisory vs info)
- Missing severity levels in skills that report findings

### 3b. Frontmatter conventions

Check all skills for consistent frontmatter fields and correct `disable-model-invocation` setting:

- **Workflow skills** (commit, ship-it, start-work) — should disable model invocation
- **Review/audit skills** (skills-review, security review) — should disable model invocation
- **Discovery skills** (whats-next, project-status) — should disable model invocation

Flag any mismatches or inconsistencies in frontmatter patterns.

### 3c. Conflicts with CLAUDE.md

Read CLAUDE.md (if it exists) and cross-reference every skill's instructions against project rules:

- **Branch policy**: Do all skills respect the project's branch policy?
- **Commit conventions**: Do all skills use the same commit message format, Co-Authored-By line, HEREDOC format?
- **Safety rules**: Do all skills respect the project's defined safety constraints?
- **Tool preferences**: Do any skills use tools or commands that CLAUDE.md discourages?
- **Permissions model**: Do skills respect what is and is not authorized?

Flag any skill instruction that contradicts or fails to enforce CLAUDE.md rules.

## Phase 4: Per-Skill Audit

For each skill, evaluate:

1. **Structure** — Has clear phases/steps, "how to use" guidance, defined output format?
2. **Domain coverage** — Missing obvious checks for its domain? (e.g., a commit skill that does not check for unstaged changes)
3. **Clarity** — Steps concrete enough to follow unambiguously? Or vague directives that could be interpreted multiple ways?
4. **Actionability** — Each check explains what to flag and what is OK? Or just lists things to "look at"?

| Skill | Structure | Coverage | Clarity | Actionability | Notes |
|-------|----------|---------|---------|--------------|-------|

Rate each dimension: Good, Adequate, Needs work.

## Phase 5: Gap Analysis

Map skills against the development lifecycle:

| Phase | Covered by | Gap? | Recommendation |
|-------|-----------|------|---------------|
| **Planning** (issue triage, task breakdown) | | | |
| **Implementing** (code generation, editing) | | | |
| **Validating** (checks, linting, testing) | | | |
| **Committing** (staged commit with checks) | | | |
| **Shipping** (push, PR creation) | | | |
| **Reviewing** (code review, security) | | | |
| **Documenting** (doc maintenance) | | | |
| **Status** (project tracking) | | | |
| **Maintenance** (skill quality, cleanup) | | | |

Only recommend new skills where the gap is material and would provide clear value. Do not recommend skills for the sake of completeness.

## Phase 6: Theme Alignment

Assess holistically across all skills:

1. **Opinionated guidance** — Do skills make decisions and provide concrete recommendations, or do they just list possibilities and leave everything to the user? Good skills are opinionated.
2. **Read-only by default** — Do skills respect the principle of not making unauthorized changes? Do any skills modify files without explicit user approval?
3. **Consistent voice** — Do all skills follow the same structural patterns? Similar heading styles, similar output formats, similar interaction patterns?
4. **CLAUDE.md alignment** — Are skills and CLAUDE.md telling the same story? Or do skills define their own rules that diverge from the project's central configuration?

## Output Format

Present the full review in this structure:

```
## Skills Review

### Inventory
[summary table from Phase 1]

### Blockers
- [skill] Conflicting or broken instructions that must be fixed

### Warnings
- [skill] Inconsistency or redundant overlap worth addressing

### Suggestions
- [skill] Improvement opportunity, not urgent

### Overlap Map
[table from Phase 2]

### Per-Skill Scorecards
[table from Phase 4]

### Gap Analysis
[table from Phase 5]

### Theme Alignment
[assessment from Phase 6]

### Passed Checks
- List of checks with no issues found
```

## Rules

- This skill is **read-only** — it never modifies skill files, CLAUDE.md, or any project files
- Evaluate all skills found, not just a subset
- Be decisive — make clear recommendations, do not hedge
- If a skill is well-written and has no issues, say so briefly and move on
- Focus audit time on skills with actual problems, not on praising good ones
