---
name: error-handling-preflight
description: "Web-framework-flavored error-handling preflight. Runs the universal core checks plus signatures specific to HTTP route handlers, async UI, and SSR/CSR boundaries."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Web Error Handling Preflight

A thin extension of `core/error-handling-preflight`. Runs the universal patterns first, then adds the checks that only make sense in a web-application context: HTTP route handlers, client/server boundaries, and event-driven UI code.

## Invocation

- `/error-handling-preflight` — run both this and the core skill against the working tree
- `/error-handling-preflight <path>` — scope to a file or directory

## Run order

1. Invoke `core/error-handling-preflight` first. Collect its findings.
2. Run the web-specific checks below.
3. Merge and report.

## Web-Specific Checks

### W1. Route handler body parsing must be in a try/catch

**Smell**: an HTTP route handler that calls `req.json()`, `req.formData()`, `req.text()`, `req.body`, `await request.body()` (or framework equivalent) at the top of the function with no surrounding try/catch.

**Why**: malformed JSON throws inside the handler. Without a catch, the framework returns a generic 500 with a stack — both a UX and a security problem.

**Fix**: wrap the parse. On failure, return a 400 with a structured error body.

```ts
try {
  body = await req.json();
} catch (err) {
  return jsonError({ code: "INVALID_JSON", status: 400 });
}
```

### W2. Route handler returns structured error responses

**Smell**: a route handler's catch block returns `error`, `error.message`, or `error.toString()` in the response body. Or returns `new Response(err.stack, { status: 500 })`.

**Why**: see rule 5 of the core skill — internal errors carry library and path information. The web layer must sanitize before responding.

**Fix**: catch blocks always return a structured `{ code, message }` object with an HTTP status. The verbose error goes to the server log; the response carries only what the client can act on.

### W3. Route handler runtime / config exports

**Smell**: a new route handler file missing `export const runtime`, `export const dynamic`, or `export const maxDuration` (framework-dependent) when the handler does I/O that exceeds platform defaults.

**Why**: silent timeouts at the edge truncate responses mid-stream. Symptoms look like network errors but the cause is config.

**Fix**: when the handler streams, calls slow upstreams, or performs long-running writes, declare the runtime explicitly.

### W4. Async function as event-handler prop

**Smell** (refinement of core rule 3 for component code):

```tsx
<button onClick={handleSubmit} />   // handleSubmit is async
```

**Why**: the framework discards the returned promise. Errors thrown in `handleSubmit` are uncaught.

**Fix**:

```tsx
<button onClick={() => { void handleSubmit().catch(reportErr); }} />
```

Or extract the async work into a function that owns its own error reporting and call it from a sync wrapper.

### W5. `"use client"` boundary on hook usage

**Smell**: a module that uses hooks (`useState`, `useEffect`, `useReducer`, etc.) or browser-only APIs (`window`, `document`, `localStorage`) without a `"use client"` directive at the top.

**Why**: the build will fail or the component will render server-side and crash on hydration. Either way, the error is not the user's domain bug — it's a wiring failure.

**Fix**: add `"use client"` to the file (for React-based frameworks). For Vue/Svelte/Solid equivalents, follow the framework's client-only directive. If the component is intentionally isomorphic, gate browser APIs with `typeof window !== "undefined"` checks.

### W6. Stream/abort handling on agent/socket/long-lived connections

**Smell**: a streaming endpoint (SSE, WebSocket, fetch with ReadableStream) that doesn't listen for `AbortSignal`, `req.signal.aborted`, or the equivalent. The stream keeps producing after the client disconnects.

**Why**: leaked sockets, leaked tokens, leaked compute. In LLM/agent contexts, this also means writing the next user's response to the previous user's UI.

**Fix**: wire `AbortSignal` from the request through to every awaited operation in the stream. Stop on `signal.aborted`. Tear down upstream subscriptions on the abort.

### W7. SSR-unsafe imports at module top

**Smell**: a server-rendered module that imports a browser-only library (e.g., something that calls `window` at import time) without dynamic `import()` or framework-specific guard.

**Why**: SSR build crashes or the first render fails. Either silently (replaced with a fallback) or loudly (500).

**Fix**: dynamic import gated by `typeof window !== "undefined"`, or move the dependency to a `"use client"` boundary.

### W8. Fetch without timeout / AbortController

**Smell** (refinement of core rule 10): a `fetch(...)` call without an `AbortController` `signal`, `timeout` option (Node `fetch`), or framework-provided timeout. Especially in server code where defaults are "never".

**Why**: one slow upstream stalls a connection pool and brings down request latency for everyone.

**Fix**: every `fetch` in server-side code carries an `AbortSignal` derived from `AbortSignal.timeout(ms)` or the request's own signal. Client-side fetches without timeouts are acceptable only when the user is actively waiting.

## How to Run

After the core skill runs, add these greps (illustrative):

```bash
# W1: req.json() outside try/catch in route handlers
rg -n -B1 'await (req|request)\.(json|text|formData)\(\)' src/app --type ts --type tsx | rg -B1 -v 'try'

# W2: error leaked in NextResponse
rg -n 'NextResponse\.json\([^)]*\b(err|error)(\.message)?\b' src/app --type ts

# W3: route handler missing runtime export
for f in $(rg -l 'export (async )?function (GET|POST|PUT|DELETE|PATCH)' src/app); do
  rg -q 'export const (runtime|maxDuration)' "$f" || echo "MISSING: $f"
done

# W4: async function passed to onClick/onChange/etc.
rg -n 'on[A-Z][a-zA-Z]+=\{[a-zA-Z_$][a-zA-Z0-9_$]*\}' --type tsx
# (cross-reference: is the identifier defined `async`?)

# W5: hook usage without "use client"
for f in $(rg -l 'use(State|Effect|Reducer|Memo|Callback|Ref|Context)\(' --type tsx); do
  head -3 "$f" | rg -q '"use client"' || echo "MISSING: $f"
done

# W8: fetch without signal/timeout in server code
rg -n 'fetch\([^)]*\)' src/app src/lib --type ts | rg -v 'signal:|AbortSignal'
```

The framework names above are Next.js-flavored. Other frameworks have analogous primitives:
- Express/Fastify: a `try`/`catch` around `req.body` parsing; framework's error middleware for responses
- SvelteKit: `+page.server.ts` actions, `event.request.signal`
- Remix: action/loader functions, `request.signal`
- Vue/Nuxt: server routes, `defineEventHandler`'s `event.node.req.signal`

Translate the pattern to the framework in use. The signatures are different; the smell is the same.

## Report Format

Append to the core skill's report under a **Web-specific findings** section, grouped by W-rule.

## Rules

1. **Run after core.** Never duplicate a universal check here.
2. **Framework names are signposts, not gates.** When the codebase uses a different framework, the framework-specific grep needs adjusting; the *check* still applies.
3. **Generated files (build output, `.next/`, `dist/`, codegen) are excluded by default.**
4. **Test files are excluded** — same rationale as the core skill.

## See also

- `core/error-handling-preflight` — universal patterns
- `core/scope-statement-check` — what is in scope for this branch
- Your framework's docs on streaming, signals, and route runtime config
