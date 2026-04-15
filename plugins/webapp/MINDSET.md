# Web Application Mindset — Principal TypeScript / Next.js / React Conventions

This document captures enterprise web application conventions distilled from
production Next.js / TypeScript / React codebases. It is intended to be
imported into a project's `CLAUDE.md` via:

```markdown
# <project> conventions

@plugins/webapp/MINDSET.md
```

Once imported, these principles become project-level guidance that applies
uniformly to every session. Override or extend individual sections in your
`CLAUDE.md` when your project's conventions diverge.

---

## Mindset

**Types are design, not decoration.** A well-typed codebase documents intent
so future changes fail at compile time instead of silently at 2am. `any`,
loose `unknown`, and overly broad generics are deferred bugs. Prefer
discriminated unions over optional properties; prefer branded types over raw
primitives on important boundaries.

**The server/client boundary is sacred.** In modern Next.js, a stray
`"use client"` poisons the entire import subtree; a leaked secret via a
Server Component prop lands in the client bundle; a server-only module
imported from a client component crashes at build. Know which file runs
where, and why. Default to Server Components; promote to Client Components
only when you need state, effects, or browser APIs.

**Data fetching is architecture, not plumbing.** Where data is fetched
(server-side, client-side, streaming, static) determines the whole app's
performance, caching, and failure behavior. Every `fetch` is a design
decision.

**Composition beats configuration.** A `variant` prop that branches on 8
values is two components pretending to be one. Small, focused components
and hooks that do one thing compose better than a large component with 15
props.

**Bundle size is user experience.** Every KB shipped to a phone on LTE
is ~8ms of parse time and some battery. Tree-shake imports, lazy-load
non-critical code, audit `@types/*` and utility libraries ruthlessly.

**Accessibility is product quality, not a checkbox.** `div` with a
click handler is a bug. Keyboard navigation is a feature. Focus
management is part of routing.

**`useEffect` is usually a bug.** Ask: can this be derived? Can this be
an event handler? Can the parent own this state? Effects are for syncing
with external systems, not for deriving values.

---

## Testing discipline

### What requires tests

Tests are **required** for:

- Utility / parsing functions — all of them
- Custom hooks
- Components with business logic, state, or conditional rendering
- API route handlers
- Database access functions
- Page and layout components with non-trivial logic
- Bug fixes — must include a regression test that fails without the fix

Tests are **not required** for:

- Pure type definitions
- Database schemas with no business logic
- Simple re-export or barrel files

### Test conventions

- Test files live **next to their source**: `foo.ts` → `foo.test.ts`.
- Use **descriptive test names**: `it("returns null when JSON is malformed")`.
- No snapshot tests — they break on any change and provide little value.
- No hardcoded dates/timestamps — use fake timers or relative values.
- Mock at **boundaries** (fetch, DB, external APIs), not at internal
  functions.
- Each test is independently runnable (no order dependencies).
- Follow AAA: Arrange, Act, Assert.

### Tests must be functional

A test that passes `"a"` as a prop and asserts `"a"` appears is worthless.
Tests must verify that code **works**, not just that it renders or passes
data through.

**Anti-patterns to avoid:**

- **Prop echo tests** — passing a value in and asserting it renders. Tests
  nothing.
- **Mock-in / mock-out tests** — mocking a dependency, calling the
  function, asserting the mock was called with the same args. Tests
  wiring, not behavior.
- **Render-only tests** — asserting a component renders without testing
  any interaction or state.
- **Shallow assertion tests** — checking that elements exist without
  verifying they respond correctly to user actions.

**What functional tests look like:**

- Click a button → verify the side effect (API call, state change,
  navigation, UI update).
- Submit a form with invalid data → verify validation errors appear.
- Trigger an error condition → verify the error UI renders and recovery
  works.
- Change state → verify dependent UI updates correctly.
- Call a function with edge-case input → verify it handles the edge case
  (not just that it calls a mock).

If a button exists, test clicking it. If content renders conditionally,
test both branches. If an element can be disabled, assert the disabled
state.

### Component tests

Component tests cover **all user-visible behavior**:

- Every interactive element (buttons, inputs, selects)
- Conditional rendering branches (empty, loading, error, data variants)
- Visual states (disabled, active, selected)

"UI rendering" is not a lower priority than "core logic." It is core
logic for users.

### Branch coverage for changed code

All changed lines and branches in the hot paths (`src/components/`,
`src/app/api/`, `src/db/`, `src/hooks/`, `src/lib/` or your project's
equivalents) should have test coverage. Type-system-unreachable branches
(e.g. nullish coalescing on typed keys) are the only acceptable exception.

---

## E2E testing

### When E2E is required

E2E tests are **required** for any source code change that affects
user-visible behavior. If you change source code, write or update an E2E
test that verifies the feature from the user's perspective — what they
see, click, type, and experience.

E2E tests cover:

- **Functionality** — does the feature work end-to-end?
- **UX** — are loading / error / empty states correct?
- **UI presentation** — does the right content appear in the right place?
- **Style and visual state** — are disabled / active / selected states
  visually correct? Does dark/light theme work?
- **Accessibility** — keyboard navigation, ARIA, focus management.

**Exempt from E2E:**

- Documentation-only changes (`.md`)
- Type-only changes (`.d.ts`, pure type files)
- Config changes with no UI impact
- Database schema files with no corresponding UI change

Do **not** write E2E tests for pure utility functions — use unit tests.

### E2E conventions

- Organize E2E by feature under `e2e/features/<feature>/`, not
  co-located with source.
- Apply tags in test names for cross-cutting filtering:
  - `@smoke` — critical path, app loads, auth works
  - `@feature` — full behavioral tests (default)
  - `@a11y` — WCAG 2.1 AA, keyboard nav, ARIA
  - `@visual` — brand / theme / layout consistency
- Example: `test('send message and receive response @feature', ...)`

### Locator priority

Prefer accessibility-first locators in this order:

1. `page.getByRole('button', {name: '...'})` — semantic roles
2. `page.getByLabel('...')` — form inputs
3. `page.getByText('...')` — visible text
4. `page.getByTitle('...')` — title attributes
5. `page.locator("[aria-label='...']")` — explicit ARIA (centralized in a
   selectors module)
6. CSS class selectors — **last resort**, must be in
   `e2e/helpers/selectors.ts` as named constants

Never use auto-generated utility-CSS classes (Tailwind), `nth-child`, or
XPath as selectors. They break on unrelated refactors.

### Page Object Model conventions

- POMs live in `e2e/helpers/<feature>-page.ts`.
- Constructor takes `Page`, methods wrap navigation and interaction.
- **No assertions in POMs** — assertions belong in test files.

### E2E isolation

- Call `cleanupEncounters()` (or your project's equivalent teardown) in
  `test.beforeEach` — tests must not depend on data from other tests.
- Custom browser contexts **must include `storageState`**. When using
  `browser.newContext()` (e.g. for mobile viewport tests), always pass
  `storageState` — without it, the app redirects to `/signin` and
  assertions fail.
- Database state setup belongs in `beforeAll` / `beforeEach` with
  matching cleanup in `afterAll`.

---

## Error handling

API routes follow a consistent pattern:

```typescript
export const POST = withAuth(async (req) => {
    try {
        const body = await req.json()
        const result = await doSomething(body)
        return NextResponse.json(result)
    } catch (error) {
        console.error(error)
        return NextResponse.json(
            { error: "Internal server error" },
            { status: 500 }
        )
    }
}, ["admin"])
```

- Wrap DB / external calls in try/catch.
- Return `NextResponse.json({ error: "message" }, { status })` on failure.
- **Never expose raw error objects to clients** — they leak stack traces,
  SQL fragments, and internal paths.
- Use a `withAuth` wrapper (or equivalent) for protected routes. Pass
  required roles / scopes as a second argument.
- Validate inputs at the boundary with a runtime schema (zod, io-ts,
  valibot). Do not trust TypeScript types for runtime inputs.

---

## Git workflow

- **Never commit directly to `main`** — create a feature branch first.
- **Always branch from latest `origin/main`** — run `git fetch origin
  main` then `git checkout -b <branch> origin/main`.
- **Never push without being asked** — the user decides when to push.
- **Never amend commits** — create new commits.
- **Never run destructive git operations** without explicit user request
  (no `git reset --hard`, `git checkout .`, `git clean -f`, `git branch -D`).
- **Documentation is required** — every feature branch must have docs in
  `docs/issues/` and/or `docs/features/` before pushing.

### Worktrees

Feature work uses git worktrees under `.worktrees/`. The main working
tree stays on `main` and is never switched to a feature branch.

- **You are in a worktree** if `pwd` is under `.worktrees/`. Work
  normally — commit, edit, test — but never switch branches within a
  worktree. The worktree IS the branch.
- **Environment files** (`.env`, `.env.test`) are gitignored and must be
  copied from the project root into each new worktree.
- **Cleanup**: remove merged worktrees with `git worktree remove
  .worktrees/<name>`. Destructive deletion requires explicit approval.

---

## Dev server and process management

- **Never start the dev server** (`npm run dev`) — the developer runs
  this in their own terminal.
- **Never stop, kill, or restart processes** — no `kill`, `killall`,
  `pkill`, `lsof -ti | xargs kill`, or similar commands.
- **Never run `npm run dev`** — not even to "help" or "verify" something
  is working.
- **Assume the dev server is already running** when the developer is
  working — they will tell you if it is not.
- **Most IDE + Claude Code users have two terminals**: their own
  (running the dev server) and the Claude Code panel. Claude operates
  only in the Claude Code panel. If the server needs restarting, tell
  the developer to do it in their terminal.

---

## Design tokens and theming

- **Never use inline hex colors.** Always use a semantic token
  (`bg-primary`, `text-foreground`, `border-border`, etc.).
- **Never use `dark:` variants for color classes.** Tokens handle dark
  mode automatically via CSS variables. Opacity variants on the same
  token are the only exception (`bg-warning/[.06] dark:bg-warning/[.08]`).
- **Use `var(--color-*)` in CSS files and inline styles** — e.g.
  `var(--color-primary)`, not `#2774AE`.
- **Core token pattern** (adapt to your project):
  - `background` / `foreground` — main surface and text
  - `card` / `card-foreground` — card surfaces
  - `muted` / `muted-foreground` — subtle surfaces and secondary text
  - `primary` / `primary-foreground` — brand and its text
  - `destructive` / `destructive-foreground` — danger actions
  - `border`, `input`, `ring` — borders and focus
- **Domain tokens** (badges, status): follow a pattern like
  `badge-{type}` for background and `badge-{type}-foreground` for text.
  Keep the naming consistent.

Adding a new token:

1. Add `--color-<name>: <value>` to the theme block in `globals.css`
   (or your project's equivalent).
2. Add the dark mode override.
3. Use it immediately as `bg-<name>`, `text-<name>`, `border-<name>`.

---

## Code quality tooling

- **ESLint flat config** with TypeScript, React, Next.js, cognitive
  complexity limits, and import-boundary enforcement.
- **Prettier** with a committed config. Format-on-save in the editor.
  Covers JS/TS/JSON/CSS/YAML only — does not format Python, Bash, or
  other non-JS languages.
- **Dead code detection** (knip or ts-prune). Non-blocking in CI but
  reviewed regularly.
- **Architecture boundaries** enforced by `import/no-restricted-paths`
  or `eslint-plugin-import-x`, mirroring any `/architecture-review`
  skill.

---

## Accessibility checklist

Treat these as correctness bugs, not nice-to-haves:

- **Semantic HTML first.** `button` for buttons, `a` for links, `nav` for
  nav, `main` for main. ARIA only where semantic HTML is not enough.
- **Every form input has a label.** Placeholder is not a label.
- **Keyboard navigable.** Tab, shift-tab, enter, escape. Focus visible.
- **Color contrast** meets WCAG AA at minimum. Test in both light and
  dark themes.
- **`alt` text for images.** Decorative images get `alt=""`, not missing
  alt.
- **Focus management on route change** — the URL changed; where did
  focus go?
- **No div-buttons.** A `div` with an `onClick` is not a button. It is
  not keyboard accessible and has no role for screen readers.

---

## Performance discipline

- **Measure before optimizing.** Ship a baseline of Core Web Vitals (LCP,
  INP, CLS) and track them over time.
- **Bundle budget per route.** Know what each page costs in JavaScript.
  A route that grew 200KB in one PR should be a blocker, not a footnote.
- **Lazy-load non-critical paths.** Modals, admin-only pages, rarely-used
  features.
- **Image optimization is not optional.** Use the framework's image
  component. Responsive sizes, modern formats, lazy loading.
- **Font loading strategy matters.** FOUT / FOIT have real UX impact.
  Self-host or preload.
- **Server Components reduce the client bundle.** Use them by default;
  promote only where interactivity requires it.

---

## Security checklist

- **XSS sinks** — audit every `dangerouslySetInnerHTML`, every
  user-controlled markdown rendering path, every URL interpolation into
  `window.location` or `<a href>`.
- **CSRF posture** — for cookie-based auth, use `SameSite=Lax` (or
  `Strict`), set `Secure` in production, validate origins on mutations.
- **Auth cookie flags** — `httpOnly`, `Secure`, `SameSite`.
- **Content Security Policy** — deploy one. Start in report-only mode,
  fix violations, then enforce.
- **Secrets in the client bundle** — never ship a secret prefixed with
  `NEXT_PUBLIC_` / `PUBLIC_` unless it is genuinely public. Audit the
  built bundle for accidental exposure.
- **SQL injection** — always parameterized queries. Drizzle, Prisma, and
  similar ORMs handle this — but raw SQL paths are common and must be
  audited.
- **Input validation at the boundary** — runtime schema (zod, etc.)
  before any DB write or external call.

---

## Project architecture defaults

A reasonable starting posture for a modern Next.js project:

- **Framework**: Next.js App Router, React, TypeScript.
- **Database**: PostgreSQL + a type-safe ORM (Drizzle, Prisma).
- **Auth**: Session-based auth with `httpOnly` cookies (NextAuth, Auth.js,
  or a vendor: Clerk, Cognito, Auth0).
- **UI**: Composition-first component library (Radix, Ark, Reach) +
  Tailwind or CSS Modules.
- **Path aliases**: `@/` → `src/`. Consistent across tsconfig, jest, and
  bundler configs.
- **E2E**: Playwright.
- **Unit**: Vitest (Jest is acceptable, but Vitest is faster for ESM).
- **Package manager**: pnpm or npm; pin with a lockfile.

---

## What you do NOT do

- You do not adopt a new framework or library unprompted — review what is
  there first.
- You do not rewrite components "for clarity" unless the reviewer asked
  for that.
- You do not fabricate performance numbers, bundle sizes, or Core Web
  Vitals metrics. If you do not have data, say "measure it."
- You do not accept "it works on my machine" as evidence.
- You do not treat "TypeScript compiles" as evidence of correctness —
  type errors at runtime are routine when types lie about reality.
- You do not leak server-only modules into client components, or
  client-only hooks into Server Components.
