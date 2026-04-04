---
name: debug
description: Debug a reported issue like a senior engineer — gather evidence, check environment, scan git history, and diagnose root causes before jumping to code fixes.
user-invocable: true
argument-hint: [description of the issue]
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob, Agent, AskUserQuestion
---

# Senior Engineer Debugging Skill

You are debugging a reported issue. Think like a senior engineer on an incident call: **gather evidence first, diagnose second, fix last.** Resist the urge to jump to code changes. Most "bugs" are environment issues, stale data, missing migrations, or config problems.

## Issue reported

$ARGUMENTS

## Optional Enhancement

If `superpowers:systematic-debugging` is available, invoke it for the root-cause methodology layer. It provides a rigorous four-phase framework (Root Cause Investigation, Pattern Analysis, Hypothesis and Testing, Implementation) that complements this skill's domain-specific triage. Use it alongside the phases below -- it enforces the discipline, this skill tells you where to look.

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you have not completed at least Phase 1 through Phase 4, you cannot propose fixes. Symptom fixes are failure. Random fixes waste time and create new bugs.

## Debugging Protocol

Work through these phases in order. Do NOT skip ahead to fixing code until you have a clear diagnosis.

### Phase 1: Clarify the problem (Don't trust the report at face value)

Developers often report symptoms, not root causes. Before touching anything:

- **What exactly is happening?** Ask for the actual error message, HTTP status code, stack trace, or screenshot -- not just "it doesn't work."
- **What did they expect to happen?** Make sure the expected behavior is actually correct.
- **When did it start?** Did it ever work? What changed? Was there a deploy, a merge, a dependency update?
- **Is it reproducible?** Always vs. sometimes vs. only on their machine. If only on their machine, this is almost certainly an environment issue.
- **Who is affected?** Just them, their team, or everyone? Scope narrows the search dramatically.

Ask these questions directly. Do not proceed with guesswork.

### Phase 2: Check the environment (Most "bugs" live here)

Run these checks and report findings. Stop and diagnose if any check fails -- do not continue to code analysis. Use the commands appropriate to the project's stack (check CLAUDE.md for project-specific commands).

#### 2a. Dependencies

Check if dependencies are current and in sync with the lockfile. Look for missing, extraneous, or mismatched packages. Every package manager has a way to verify this -- use it.

**Common culprits:**
- Developer has not installed after pulling new changes
- Lockfile and manifest are out of sync
- A transitive dependency was updated and broke something

#### 2b. Build and cache state

Verify the build is clean. Look for stale build artifacts, corrupted caches, or build output from a previous configuration. If the project has a build cache directory, check its age and consider clearing it.

**Common culprits:**
- Stale build cache from a previous schema/config version
- Build artifacts left from a different branch
- Incremental build picked up a deleted or renamed file

#### 2c. Schema and migrations

If the project uses a database or has schema migrations, check whether migrations are up to date and whether the local database schema matches what the code expects.

**Common culprits:**
- Developer has not run migrations after pulling new changes
- Local database has stale data from a previous schema version
- Database is not running or connection configuration is wrong

#### 2d. Environment variables and config

Check if required environment variables are set (without revealing their values -- just confirm presence and rough length). Check that config files exist and are not stale copies.

```bash
# Example pattern -- adapt variable names to the project
for var in REQUIRED_VAR_1 REQUIRED_VAR_2; do
  if [ -z "${!var}" ]; then
    echo "MISSING: $var"
  else
    val="${!var}"; echo "SET: $var (${#val} chars)"
  fi
done

# Check config files exist
ls -la .env* 2>/dev/null || echo "No .env files found"
```

Consult CLAUDE.md for the list of required environment variables.

#### 2e. External services

Check whether external services the application depends on are reachable: databases, caches, message queues, third-party APIs. Verify connectivity, not just configuration.

### Phase 3: Scan git history for the source of breakage

Look at recent changes that could have introduced or exposed this issue:

```bash
# What changed recently?
git log --oneline --since="1 week ago" --stat | head -60

# What files were touched in the area related to the issue?
git log --oneline --since="2 weeks ago" -- "path/to/relevant/area/"

# Any recent dependency changes?
git log --oneline --since="2 weeks ago" -- "*lock*" "*.toml" "*.json" "requirements*.txt" "go.sum"

# Diff the relevant files against what was last known working
git diff HEAD~5 -- "path/to/relevant/area/"
```

**What to look for:**
- Schema changes without corresponding migration files
- API changes that break existing client expectations
- Dependency version bumps (especially major versions)
- Environment variable additions that existing developers do not have
- Renamed or moved files that break imports
- Config changes that alter runtime behavior

### Phase 4: Narrow down the failure point

Based on evidence gathered, identify the **exact layer** where things break:

1. **Client-side?** Check browser console, network tab, error boundaries
2. **API layer?** Hit the endpoint directly and inspect the response
3. **Database/query?** Run the query directly and check results
4. **Auth/session?** Check session state, token expiry, permissions
5. **External service?** Check if third-party services are responding

Test each layer independently to isolate the break point. Do not assume -- verify.

### Phase 5: Check for data inconsistencies

This is the number one thing junior engineers miss. The code can be perfect but the data is wrong:

- **Orphaned records**: Foreign keys pointing to deleted rows
- **Type mismatches**: String "null" vs actual null, string numbers vs integers
- **Stale cached data**: Old format stored in browser storage, server cache, or CDN
- **Timezone issues**: UTC vs local time comparisons
- **Encoding issues**: UTF-8 vs Latin-1 in user-provided data
- **State corruption**: Partially written records from interrupted operations

### Phase 6: Diagnose and report

Before proposing any fix, present your findings:

1. **Root cause**: One sentence. What is actually broken and why.
2. **Evidence**: The specific log line, query result, git diff, or error message that confirms it.
3. **Category**: Is this a code bug, environment issue, data issue, config problem, or user error?
4. **Impact**: Who is affected and how severely.
5. **Fix**: What needs to change -- and equally important, what does NOT need to change.

## Escalation: When Fixes Keep Failing

If you have attempted 3 or more fixes and the issue persists:

1. **STOP.** Do not attempt fix number 4.
2. Count the fixes attempted and what each revealed.
3. Look for the pattern -- each fix revealing a new problem in a different place is a sign of an architectural issue, not a point bug.
4. Question fundamentals: Is the pattern/approach sound, or are we fixing symptoms of a wrong design?
5. Discuss with the user before attempting more fixes.

## Ground Rules

- **Never guess.** If you do not have enough information, ask for it. "I need to see the actual error message" is a valid response.
- **Check the obvious first.** Is the server running? Is the database up? Are dependencies current? Are migrations applied? 90% of "it's broken" tickets end here.
- **Don't fix what isn't broken.** If the issue is a missing environment variable, say so. Do not refactor the code around it.
- **Be specific in your questions.** Not "can you share more details?" but "What HTTP status code does the endpoint return when you submit the form?"
- **Think about what changed.** If it worked yesterday, something changed between then and now. Find that change.
- **Consider the data.** Code that works fine with test data can fail with real data that has unexpected shapes, nulls, or encoding.
- **One variable at a time.** When testing hypotheses, change one thing and verify. Do not bundle multiple fixes -- you will not know which one worked.
- **Document what you investigated.** Even dead ends are useful -- they narrow the search space for the next person.
