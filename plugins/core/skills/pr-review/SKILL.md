---
name: pr-review
description: Reviewer-side PR workflow — checks out the branch in a worktree, runs focus-area reviews plus a senior-engineering pass, optionally cross-checks against an autonomous reviewer, and posts inline findings only on explicit approval. Read-only — never edits, commits, or pushes.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion
---

# PR Review -- Reviewer-Side Workflow

Companion to `/pr-fix` (which triages incoming review feedback on *your* PR). This skill is what you run when **you are the reviewer**: fetch the PR, check it out in a worktree, run focus-area reviews scoped to the diff, layer on senior-engineering judgment, cross-check any autonomous reviewer, and post inline comments only after explicit approval. Never edits source. Never commits. Never pushes.

## How to use

Invoke as `/pr-review <PR-number>` or `/pr-review <PR-URL>`. With no argument, ask which PR.

## Invariants

- **Read-only.** Never `Edit`, `Write`, run formatters or autofix linters, or any state-changing git command on the PR branch. Never commit. Never push.
- **Worktree-first.** `gh pr diff` alone is insufficient — it omits surrounding context, adjacent code, schemas, and call sites. Always check out the branch in a worktree before drafting findings.
- **Don't duplicate an autonomous reviewer.** If the PR already has a review from an autonomous reviewer (any bot), read it first and avoid restating its findings.
- **Respect scope.** Out-of-scope improvements get deferred with a one-line rationale, never posted as inline blockers.

## Configuration

`/pr-review` reads configuration from CLAUDE.md when present. Precedence: project `CLAUDE.md` > user `~/.claude/CLAUDE.md` > skill defaults. Knobs:

- **`pr-review.focus-areas`** — list of `{ name, description, skill? }` entries. Replaces, reorders, or extends the merged focus-area list.

## Steps

### 1. Resolve the PR and fetch context

```bash
# Resolve PR number, branch, repo, author
gh pr view <N-or-URL> --json number,title,headRefName,baseRefName,headRepository,author,body,additions,deletions,changedFiles,labels

# Files changed
gh pr diff <N> --name-only

# Existing reviews and comments (including any autonomous reviewer's sticky comment)
gh api --paginate repos/{owner}/{repo}/pulls/<N>/reviews
gh api --paginate repos/{owner}/{repo}/pulls/<N>/comments
gh api --paginate repos/{owner}/{repo}/issues/<N>/comments
```

Identify any sticky-comment review from an autonomous reviewer (look for `user.type == "Bot"` or a single comment that gets edited in place across pushes). Read it. Note what it already flagged so you don't restate it in Step 8.

### 2. Check out the branch in a worktree (REQUIRED)

```
/checkout <headRefName>
```

`/checkout` creates a worktree under `.worktrees/<branch-as-dashes>/` at repo root. From this point on, all file reads must come from the worktree, not from `main`. Verify with `pwd`.

If the PR is from a fork, `/checkout` may need adjustment — confirm with the user before proceeding.

### 3. Extract the scope contract

```
/scope-statement-check extract <linked-issue-or-PR-body>
```

The PR body usually links an issue (`Closes #N` / `Fixes #N`). If no linked issue exists, extract scope from the PR title + description. The skill writes the contract to `.scope/<branch>.md`. You'll use this in Step 7 to classify findings as in-scope vs. out-of-scope.

If `/scope-statement-check` is not available, skip and rely on judgment in Step 7. Suggest the user install or enable the skill.

### 4. Build the focus-area list and ask the reviewer

Assemble the list of focus areas in this order:

1. **Four baked-in defaults** (always present unless replaced by CLAUDE.md):
   - **Security** — auth, input validation, secrets, data exposure
   - **Architecture** — boundaries, layering, dependency direction, complexity
   - **Tests** — coverage of new behavior, regression coverage, test quality
   - **Docs** — README, inline comments, accuracy of changed-area documentation
2. **Contributing skills discovered at runtime.** Scan the available-skills list from the current session context. For every skill whose `description` field begins with the marker `[pr-review-focus-area: <Name>]`, add `<Name>` as a focus area and record the skill's fully-qualified name (e.g., `infra:review-aws-iam`) so Step 5 can invoke it.
3. **CLAUDE.md overrides.** If `pr-review.focus-areas` is defined, apply it: entries can replace the merged list entirely, reorder it, or add to it. Last-wins on display-name collisions; surface the conflict in the AskUserQuestion description.

Present the merged list to the reviewer via `AskUserQuestion` (multi-select):

> **Which areas should this review focus on?**
> *(The senior-engineering pass runs regardless. Select any domains that deserve extra depth.)*

If the reviewer skips the question, infer focus from the changed file paths and the default list. When nothing maps cleanly, default to **Security + Architecture** plus the senior-engineering pass.

### 5. Run the selected focus-area reviews

For each selected focus area:

- If the area has an associated **contributing skill** (from discovery or from CLAUDE.md), invoke that skill scoped to the PR's changed files only — don't re-scan the repo.
- If the area has no associated skill (a baked-in default with no marker match), the senior-engineering pass in Step 6 covers it.

Capture each skill's findings (severity + `path:line` + description). Don't post yet — accumulate everything for Step 7.

### 6. Senior-engineering pass (always runs)

This is the layer that bots and individual focus-area skills miss. Apply judgment to the full diff in the worktree.

#### Read with the whole-file lens

For each non-trivial changed file, read the **whole file** (not just the diff hunks). The diff hides:
- A new function that duplicates an existing helper elsewhere in the codebase
- A new component that re-implements a pattern already present
- An import added but the original is still imported above
- A condition that's already enforced upstream and is now double-guarded

#### Stack-agnostic smells to look for

| Smell | What to look for |
|---|---|
| Duplicated logic | Same conditional, parsing, or formatting in 2+ places — should be a shared util |
| Misplaced abstraction | Helper used once, only by one caller — inline it; or a feature-specific util sitting in a shared `lib/` |
| Leaky abstraction | A consumer receiving a data shape it shouldn't know about; a util returning raw lower-layer types to a higher layer |
| Premature flexibility | New config knob with one caller; new generic with one type argument; "in case we need to…" |
| Mock-in/mock-out tests | Tests that mock a dependency and assert the mock was called — they test wiring, not behavior |
| Echo tests | Test passes value `X` in and asserts `X` comes out — worthless |
| Snapshot tests | Brittle; flag any introduced without a justifying comment |
| Magic numbers/strings | Inline literals that would be clearer as named constants |
| Inconsistent error handling | Some paths catch & return generic errors, this one bubbles raw internals |
| Naming drift | New name conflicts with established vocabulary in the codebase |
| Backwards-compat shims | "For now" wrappers, re-exports, type forwarders without a deprecation plan |
| Comments that restate code | Doc comments that say what well-named code already says |
| Comments where code was removed | "// X intentionally removed" instead of just removing it |

#### Complexity & maintainability

- Functions that grow long (≥100 lines) without being a clear dispatcher/switch deserve a "consider splitting" suggestion.
- More than 3 levels of nested conditional / ternary / `&&` chains is a smell — suggest early returns or extraction.
- New effect-style hooks with complex dependency arrays: does it need to be an effect, or is it derived state masquerading as one?

#### Risk-aware reading

For high-blast-radius changes, push back even if the diff is small:
- Auth/permission changes
- Schema or data-shape changes (especially destructive ones)
- Shared state / context that re-renders cascade through
- Endpoints or surfaces returning user data — verify field selection
- CI/CD configuration — out-of-repo blast radius

#### Test coverage judgment

Beyond presence:
- Bug fix → is there a regression test that would fail without the fix?
- New conditional rendering → are both branches tested?
- New endpoint or interface → does the test mock at the boundary or at internal functions (anti-pattern)?

### 7. Classify findings against scope

For every finding from Steps 5 and 6, tag with a scope classification using the contract from Step 3:

- **in-scope** — both path and subject fall inside the contract → eligible for inline posting
- **out-of-scope-surface** — file is outside the contract's touched surfaces → defer with rationale
- **out-of-scope-subject** — file is touched, but the finding asks for something the contract excluded → defer with rationale
- **ambiguous** — judgment call; default to in-scope and mark for the reviewer

For deferred findings, generate a one-line rationale:

```
Deferring — outside scope of this PR (<one-line contract reference>).
Consider a follow-up issue if this matters.
```

The reviewer can edit before posting.

### 8. Cross-check against any autonomous reviewer (conditional)

If the PR has a sticky-comment review from an autonomous reviewer (identified in Step 1), re-read it. For each of your accumulated findings:

- **Already flagged, same severity** → drop yours; optionally agree in the summary
- **Already flagged but you disagree** → keep yours, frame as a reply to the bot's comment ("Counterpoint: …")
- **Bot missed it** → keep, post as new inline comment
- **Bot flagged but is wrong or stale** → note in the summary so the author isn't asked to fix a non-issue

If no autonomous review exists, skip this step.

### 9. Present the matrix

Output the consolidated findings as a table grouped by recommendation:

| # | File | Line | Severity | Source | Scope | Finding |
|---|------|------|----------|--------|-------|---------|
| 1 | `path/to/file` | 42 | Blocker | <focus-area-skill> | in-scope | <one-line summary> |
| 2 | `path/to/other` | 88 | Warning | senior-eng | in-scope | <one-line summary> |

Below the table, summarize:
- Total findings, breakdown by severity
- Anything where focus-area skill + senior pass + bot all agreed (high confidence)
- Anything where you disagree with the bot
- Bot findings that look stale or wrong (so the author can dismiss)

Then `AskUserQuestion`:

> **Which severity tier should I draft for posting?**
> - **All in-scope** — every in-scope finding
> - **Blockers + Warnings** — skip Suggestions
> - **Blockers only** — minimum-noise review
> - **Cancel** — don't draft anything

### 10. Draft the exact comments and review summary, then WAIT

**Nothing is posted yet.** Build the full payload locally and show it to the reviewer for approval.

For each finding in the selected tier, print the exact inline comment body:

```
### Draft inline comments

#### 1. `path/to/file:42` — Blocker
**`path/to/file:42`** (blocker)
<one-paragraph explanation>

<optional suggested fix>

#### 2. `path/to/other:88` — Warning
...
```

Then print the draft review summary that will accompany them:

```
### Draft review summary
<summary text — includes any "Deferred — out of scope" section and any "Bot findings that look stale" notes>
```

Then `AskUserQuestion`:

> **Ready to post this review?**
> - **Post as-is** — file every drafted inline comment and submit the review (event=COMMENT)
> - **Edit first** — tell me which comments to revise; I'll redraft and re-ask
> - **Drop some** — tell me which to omit; I'll re-ask before posting
> - **Cancel** — don't post anything

**Do not call `gh api ... /comments` or `gh api ... /reviews` until the reviewer selects "Post as-is".** Drafts are not commitments. Any other answer loops back to redraft and re-ask. Silence is not approval. "Looks fine" in chat is not approval. Only the AskUserQuestion answer counts.

### 11. Post the review (only after explicit approval)

Once the reviewer selects **Post as-is**, file the inline comments and submit the review:

```bash
# One per inline finding — references commit SHA, path, line
gh api repos/{owner}/{repo}/pulls/<N>/comments \
  -f body="<comment body>" \
  -f commit_id="<head_sha>" \
  -f path="<path>" \
  -F line=<line> \
  -f side=RIGHT

# Submit the review with summary + event
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  -f body="<summary>" \
  -f event=COMMENT
```

**Default `event` to `COMMENT`.** Do not auto-approve. Do not auto-request-changes. The reviewer decides whether to flip to `APPROVE` or `REQUEST_CHANGES` after seeing the posted findings — surface the choice explicitly.

Halt on the first non-2xx response and report which comment failed so the reviewer can correct and retry.

Comment body format (uniform across human and bot reviews):

```
**`path/to/file:42`** (blocker|warning|suggestion)
<one-paragraph explanation of the issue and the reasoning>

<optional: suggested fix or pointer to existing helper>
```

For deferred (out-of-scope) findings, do NOT post inline. Include them in the review summary under a "Deferred — out of scope" section so the author can open follow-up issues without feeling pressured to fix in this PR.

### 12. Stop

Do not edit source. Do not commit. Do not push. The PR review is the deliverable. If the author asks you to apply fixes, they should run `/pr-fix` from their side — that's the separation of concerns this skill enforces.

## Contributing focus areas from other skills

Any skill in any installed plugin can contribute a focus area to `/pr-review` by prefixing its `description:` frontmatter value with a marker:

```yaml
---
name: my-domain-review
description: "[pr-review-focus-area: My Domain] Reviews <X> in changed files for <Y>."
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
---
```

Shape: `[pr-review-focus-area: <Display Name>]` followed by a single space, then the regular human-readable description. The display name is what the reviewer sees in Step 4's AskUserQuestion.

Discovery is runtime — `/pr-review` scans the harness-provided available-skills list and matches skills by this marker. Installing the contributing plugin (user-global or project-local) is the entire integration step; no `core` changes required.

## Quick reference

| Step | Action | Tool |
|------|--------|------|
| 1 | Fetch PR + existing reviews | `gh pr view`, `gh api` |
| 2 | Worktree checkout | `/checkout <branch>` |
| 3 | Extract scope contract | `/scope-statement-check extract` |
| 4 | Build focus-area list + ask | `AskUserQuestion` |
| 5 | Run focus-area skills (scoped) | discovered or default skills |
| 6 | Senior-engineering pass | Read whole files; apply judgment table |
| 7 | Classify scope | `/scope-statement-check classify` |
| 8 | Cross-check autonomous reviewer (conditional) | `gh api .../reviews` |
| 9 | Present matrix | output + `AskUserQuestion` (severity tier) |
| 10 | Draft exact comments + summary, **WAIT** | output + `AskUserQuestion` (Post as-is / Edit / Drop / Cancel) |
| 11 | Post inline + review (COMMENT event) — only after Post as-is | `gh api` |
| 12 | Stop — no edits, no commits, no pushes | — |

## Common mistakes

- **Reviewing from `gh pr diff` only** — you'll miss adjacent context. Always check out.
- **Restating an autonomous reviewer's findings** — wastes the author's time. Cross-check first.
- **Posting "consider…" suggestions for out-of-scope items as inline comments** — they belong in the deferral list, not the diff.
- **Defaulting to `REQUEST_CHANGES`** — that's a human decision, not the skill's default.
- **Running autofix linters or formatters in the worktree** — read-only means read-only.
- **Re-running focus-area reviews repo-wide** — always scope to the PR's changed files.
- **Skipping the scope contract** — without it, "while you're here…" suggestions drown the author.
- **Posting before explicit approval** — Step 10 drafts only. `gh api ... /comments` and `gh api ... /reviews` are forbidden until the reviewer answers "Post as-is" via AskUserQuestion. Silence is not approval.
