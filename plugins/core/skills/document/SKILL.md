---
name: document
description: Create or update feature and issue documentation through an interactive questionnaire.
user-invocable: true
argument-hint: [issue number, feature name, or blank for auto-detect]
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob, Edit, Write, Agent, AskUserQuestion
---

# Document

Create or update project documentation in `docs/features/` and `docs/issues/`. Driven by an interactive questionnaire that gathers intent, scope, and relationships before generating content.

## Scope

This skill documents **application features and issues** -- user-facing behavior, source code architecture, bug fixes, etc. It does NOT cover:

- **Skill files** -- skill files are self-documenting via their SKILL.md
- **Documentation files** -- docs do not need docs about themselves
- **CI/config files** -- not application features

If invoked for non-source changes, tell the user these do not need documentation and stop.

## How to use

```
/document                    # Auto-detect from branch changes
/document 231                # Create/update issue doc for #231
/document agent-switching    # Create/update feature doc
```

## Phase 1: Detect Scope

### 1a. Parse argument

- **Number** (e.g., `231`): Issue doc mode -- target is `docs/issues/{number}-{slug}.md`
  - Fetch the issue: `gh issue view <number> --json number,title,body,labels,comments`
  - Derive slug from title (kebab-case, 2-4 words)
- **Name** (e.g., `agent-switching`): Feature doc mode -- target is `docs/features/{name}.md`
- **No argument**: Auto-detect from branch changes

### 1b. Auto-detect (no argument)

```bash
git diff --name-only origin/main...HEAD
git log --oneline origin/main..HEAD
```

Analyze changed files to determine:
- Which feature area(s) are affected
- Whether the branch relates to a GitHub issue (check branch name for issue numbers, check PR body)

If a GitHub issue is detected, enter issue doc mode. Otherwise, enter feature doc mode.

### 1c. Check for existing docs

**Issue docs**: Check if `docs/issues/{number}-*.md` already exists.
- If exists: read it, enter update mode
- If not: enter create mode

**Feature docs**: Smart auto-detect:

1. Grep `docs/features/` for content matching changed files, component names, and feature terms
2. Present matches to the user:

```
Found existing feature docs that may cover this work:
1. docs/features/authentication-flow.md -- mentions auth middleware
2. docs/features/search.md -- mentions SearchService

Update one of these, or create a new feature doc?
```

3. If creating new, note which existing docs should get cross-references added

## Phase 2: Codebase Exploration

Before the questionnaire, gather context:

1. Read all changed files on the branch to understand what was built/fixed
2. If issue doc mode: read the GitHub issue body and comments
3. Read existing docs in the target area for context and cross-referencing
4. If the change spans multiple areas, use the `Agent` tool with `subagent_type: "Explore"` for parallel exploration

## Phase 3: Questionnaire

Generate 2-4 targeted questions using a single `AskUserQuestion` call. Questions must be **specific to the detected changes** -- not generic.

Pick from these categories based on what Phases 1-2 found:

**Intent** (always ask):
- "What is the user-facing purpose of this [feature/fix]? What problem does it solve?"
- "In one sentence, what should someone reading this doc understand about why this exists?"

**Scope** (ask when ambiguous):
- "Does this change an existing feature or introduce a new capability?"
- "The changes touch [area A] and [area B]. Should this be one doc or two?"

**Audience** (ask for new feature docs):
- "Who needs this doc? Developers only, or also ops/non-technical stakeholders?"
- "Should this doc include operational details (monitoring, deployment) or just architecture?"

**Relationships** (ask when cross-references are relevant):
- "This relates to [existing feature doc]. Should we update that doc too, or just cross-reference?"
- "Are there related issues that should be linked?"

### Constraints

- Always ask at least 2 questions, never more than 4
- Each question should have 2-4 concrete answer options
- Reference specific files, components, or existing docs -- be concrete
- Never ask questions whose answers are obvious from the code or issue

## Phase 4: Generate Documentation

### Issue doc -- create mode

Write to `docs/issues/{number}-{slug}.md`:

```markdown
# {Issue Title}

**Issue**: [#{number}]({url})
**PR**: [#{pr}]({pr_url}) (if exists)
**Branch**: `{branch}`
**Date**: {today}

## Problem

{What is broken or missing -- from issue body, comments, and codebase analysis.
Explain the user-visible impact and the technical context.}

## Root Cause

{Technical analysis from code exploration -- what specifically causes the problem.
Reference files and line numbers. Explain why, not just what.}

## Fix

{What was changed and why -- organized by file/area.
For each significant change, explain the reasoning.}

### {Area 1}
- {change description}

### {Area 2}
- {change description}

## Testing

{How the fix was verified:}
- Unit tests: {test files added/modified, what they cover}
- Integration/E2E tests: {test files added/modified, journeys covered}
- Manual verification: {steps to reproduce and verify the fix}

## Related

- [#{related_issue}]({url}) -- {title}
- [docs/features/{feature}.md](../features/{feature}.md) -- {why it is related}
```

### Issue doc -- update mode

Read the existing doc, then update sections that have changed:
- If the fix evolved, update the "Fix" section
- If new tests were added, update "Testing"
- Add new "Related" links if discovered
- Use `Edit` to modify specific sections, do not rewrite the whole file

### Feature doc -- create mode

Write to `docs/features/{feature-name}.md`:

```markdown
# {Feature Name}

{2-3 sentence summary of what this feature does from the user's perspective.
Focus on the "what" and "why", not implementation details.}

## Key files

| File | Role |
|------|------|
| `path/to/file` | {what this file does in the context of the feature} |

## How it works

{Technical explanation of the feature:
- Data flow from user action to result
- Component interaction and state management
- Key boundaries (server/client, service layers, etc.)
- Key algorithms or business logic}

### {Subsystem 1}

{Detailed explanation of a key subsystem if the feature is complex enough to warrant subsections.}

## User journeys

{Key user flows this feature supports:}

### {Journey 1}: {Name}

1. User does {action}
2. System responds with {result}
3. User sees {outcome}

## Edge cases

{Known edge cases, error states, boundary conditions:}

- **{Case}**: {What happens and how it is handled}

## Testing

{How this feature is tested:}

- **Unit tests**: {test file paths, what they cover}
- **Integration/E2E tests**: {test file paths, journeys they verify}
- **Coverage gaps**: {known gaps, if any}

## Related

- [#{issue}]({url}) -- {title}
- [docs/features/{other}.md]({other}.md) -- {relationship}
- [docs/issues/{number}-{slug}.md](../issues/{number}-{slug}.md) -- {relationship}
```

### Feature doc -- update mode

Read the existing doc, then:
1. Update sections affected by the branch's changes
2. Add new key files if the change introduced new files
3. Update user journeys if behavior changed
4. Add new edge cases if discovered
5. Update testing section with new test files
6. Use `Edit` to modify specific sections, do not rewrite unchanged content

## Phase 5: Update Cross-References

If creating a new feature doc:

1. Scan existing `docs/features/` files for content that relates to the new feature
2. Add a cross-reference in the "Related" section of each related doc:
   ```markdown
   - [docs/features/{new-feature}.md]({new-feature}.md) -- {brief description of relationship}
   ```
3. Use `Edit` to append to the "Related" section -- never rewrite unrelated content

If creating or updating an issue doc:
1. Check if a related feature doc exists
2. If so, ensure the issue doc links to it in "Related"

## Phase 6: Present and Confirm

Display the generated/updated doc inline, then ask the user with `AskUserQuestion`:

**Options**:
1. **Save as-is** -- Write the file (or apply edits for updates)
2. **Revise with feedback** -- Provide changes, regenerate, re-present
3. **Cancel** -- Discard, no files written

After saving, report:

```
## Documentation Updated

- Created/Updated: docs/{type}/{filename}.md
- Cross-references updated: {list of other docs modified, if any}

Next: Run /commit to commit your work, or /ship-it to push.
```

## Rules

- **Never overwrite rich existing content** -- update specific sections, do not rewrite the whole file
- **Never commit** without being asked -- the user decides when to commit
- **Never push** without being asked
- **Preserve existing structure** -- if an existing doc has custom sections, keep them
- **One doc per invocation** -- if both issue and feature docs are needed, tell the user to run `/document` twice
- **Use active voice, present tense** in generated documentation
- **Terminology** -- follow project-specific terminology conventions defined in CLAUDE.md
- **Cross-references use relative paths** -- `../features/foo.md` not absolute paths
