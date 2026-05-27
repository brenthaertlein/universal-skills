---
name: a11y-review
description: "[pr-review-focus-area: Accessibility] Review changed UI files for the small set of accessibility patterns that account for most a11y review-cycle blockers."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Accessibility Review

A focused review for the high-frequency, high-impact a11y patterns that get flagged in code review. Not a substitute for `axe-core`, screen-reader testing, or a WCAG audit — but the checks below catch the patterns that keyboard-only users and assistive-tech users hit *first*, and that ship most often.

Every check has a clear smell, a clear failure mode, and a clear fix.

## Invocation

- `/a11y-review` — review changed component files in the working tree
- `/a11y-review <path>` — scope to a file or directory

## Scope

Targets component-like files: `.tsx`, `.jsx`, `.vue`, `.svelte`, `.astro`. Skips storybook stories, tests, and generated files unless explicitly passed.

## Checks (blockers)

### A1. `role="button"` requires `tabIndex` and keyboard handlers

**Smell**: `<div role="button" onClick={...}>` or `<span role="button" onClick={...}>` without `tabIndex` and without `onKeyDown`/`onKeyUp` handling Enter and Space.

**Failure mode**: keyboard users cannot focus or activate the element. Screen reader users hear "button" but pressing Enter does nothing.

**Fix**: prefer a real `<button>`. If `role="button"` is unavoidable (e.g., inside an `<a>`-rooted layout), add `tabIndex={0}` and an `onKeyDown` that handles `Enter` and `Space` and calls `preventDefault()` on Space.

```tsx
<div
  role="button"
  tabIndex={0}
  onClick={fn}
  onKeyDown={(e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      fn();
    }
  }}
/>
```

### A2. Decorative SVGs need `aria-hidden="true"`

**Smell**: inline `<svg>` used as an icon (purely decorative, no standalone meaning) without `aria-hidden="true"` or an `aria-label`/`<title>`.

**Failure mode**: screen readers may announce the SVG's path data or child element names — "path, path, path, button".

**Fix**: decorative icons get `aria-hidden="true"` and `focusable="false"`. Meaningful icons get a label.

```tsx
<svg aria-hidden="true" focusable="false">…</svg>
<svg role="img" aria-label="External link">…</svg>
```

If the icon is the *only* content of a clickable element, label the parent (`aria-label` on the button) and mark the SVG `aria-hidden`.

### A3. `outline-none` requires a visible focus replacement

**Smell**: a focusable element with `outline-none`, `outline: none`, or equivalent (`focus:outline-0` in utility frameworks) and no replacement focus indicator (`focus-visible:ring-*`, `:focus-visible { box-shadow: ... }`, etc.).

**Failure mode**: keyboard users have no idea what's focused.

**Fix**: remove `outline-none`, or pair it with a `focus-visible` replacement that meets WCAG SC 2.4.7 contrast/visibility.

### A4. `role="tab"` must be inside a `[role="tablist"]`

**Smell**: an element with `role="tab"` not nested under an ancestor with `role="tablist"`.

**Failure mode**: screen readers don't expose the tab list structure. Tab navigation between tabs doesn't work as expected.

**Fix**: wrap tabs in `<div role="tablist">`. Each tab's `aria-controls` references the `id` of its `role="tabpanel"`. Each panel's `aria-labelledby` references its tab.

### A5. Heading elements must not act as buttons

**Smell**: `<h1>` through `<h6>` with `role="button"`, `onClick`, or `tabIndex`.

**Failure mode**: a screen reader user navigating by headings (one of the most common patterns) hears the element as both a heading *and* a button. The page outline breaks.

**Fix**: nest a `<button>` *inside* the heading.

```tsx
<h3>
  <button onClick={toggle}>Section Title</button>
</h3>
```

The heading semantics remain; the click target is a real button.

### A6. `maximumScale: 1` blocks pinch-zoom (WCAG 1.4.4)

**Smell**: a viewport meta tag with `maximum-scale=1`, `user-scalable=no`, or `minimum-scale` set high enough to prevent zoom.

**Failure mode**: low-vision users cannot pinch-zoom the page. This is an *automatic WCAG AA failure* (SC 1.4.4 Resize Text).

**Fix**: remove the constraint. If you need to prevent zoom on a specific gesture (rare and almost never the right call), use `touch-action: manipulation` on the offending element instead.

### A7. Modal/dialog patterns require focus management

**Smell**: a component that conditionally renders a modal/dialog with `role="dialog"`, `aria-modal="true"`, or fixed-positioned overlay markup, but does not:
- Move focus into the dialog when it opens
- Restore focus to the trigger when it closes
- Trap focus within the dialog while open
- Respond to `Escape`

**Failure mode**: keyboard users escape into the document below the modal, screen readers wander out of the dialog, and there's no way to dismiss without a mouse.

**Fix**: use the platform's `<dialog>` element (with `showModal()`) or a vetted dialog primitive (Radix, Headless UI, Reach, framework equivalents). If hand-rolling, implement all four behaviors explicitly.

### A8. `aria-label` content must match the field's accepted input

**Smell**: an `aria-label` containing "number" on an input or interactive element that accepts non-numeric content (e.g., `aria-label="Room number"` on a field that accepts "A12", "B7", "Ward 3").

**Failure mode**: screen readers announce "Room number" and assistive tech / voice input expects digits. Users dictate "Alpha twelve" and the field rejects it.

**Fix**: name the field for what it accepts: `aria-label="Room"` or `aria-label="Room identifier"`. Use `inputMode="numeric"`/`type="number"` only when the field genuinely accepts numbers.

## Advisory Checks

These show as `[WARN]` rather than blockers — context-dependent.

### A9. Color as the sole indicator of state

**Smell**: an element whose only difference between states is color (red/green error/success, blue/grey active/inactive).

**Fix**: pair color with an icon, text, or border-style change. Color is one channel of three (color + shape + text).

### A10. Click handlers on non-interactive elements without role

**Smell**: `onClick` on `<div>`, `<span>`, `<p>`, etc., with no `role`, `tabIndex`, or keyboard handler.

**Fix**: prefer `<button>` or `<a>`. If layout requires a non-interactive parent, move the handler to a real interactive child.

### A11. Form inputs without associated labels

**Smell**: `<input>` without a `<label htmlFor>`, `aria-label`, or `aria-labelledby`.

**Fix**: every input has an associated label. Placeholder is *not* a label — it disappears on focus.

## How to Run

Run greps against the target file set. Patterns are illustrative (TSX-flavored); adapt to the project's component language.

```bash
# A1: role="button" without tabIndex/onKeyDown
rg -n 'role="button"' --type tsx | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  # Check the same element for tabIndex and onKeyDown — context-sensitive, use a parser if possible
done

# A2: SVG without aria-hidden or aria-label
# Note: uses PCRE2 lookahead — requires rg built with PCRE2 support (rg -P)
rg -Pn '<svg(?![^>]*aria-(hidden|label))' --type tsx

# A3: outline-none / focus:outline-0 without focus-visible:ring
rg -n 'outline-none|outline:\s*none|focus:outline-0' --type tsx --type css

# A4: role="tab" — verify parent has role="tablist" (requires AST or careful grep)
rg -n 'role="tab"' --type tsx

# A5: heading with role=button / onClick
rg -n '<h[1-6][^>]*\b(role="button"|onClick)' --type tsx

# A6: viewport maximumScale: 1 or user-scalable=no
rg -n 'maximumScale\s*:\s*1|user-scalable=no' --type ts --type tsx --type html

# A7: modal-like markers — manual review trigger
rg -n 'role="dialog"|aria-modal="true"' --type tsx

# A8: aria-label containing "number" — manual triage
rg -n 'aria-label="[^"]*[Nn]umber' --type tsx
```

A static-analyzer approach (e.g., `eslint-plugin-jsx-a11y` or framework equivalent) catches many of these structurally. This skill is a complement, not a replacement — it focuses on the patterns that bots most often miss or get wrong in practice.

## Report Format

```
## A11y Review

### Blockers (N)
- A1 — `src/components/Card.tsx:42` — `<div role="button" onClick={…}>` missing `tabIndex` and keyboard handler
- A6 — `src/app/layout.tsx:18` — `maximumScale: 1` blocks pinch-zoom (WCAG SC 1.4.4)

### Warnings (M)
- A9 — `src/components/Status.tsx:30` — error state distinguished only by color

### Verdict
BLOCK if any A1–A8 finding remains unresolved. A9–A11 are advisory.
```

## Rules

1. **Static greps are starting points.** A1, A4, A7 need structural inspection (AST or careful read) to confirm. Always read the file before deciding.
2. **Use the platform first.** `<button>`, `<a>`, `<dialog>`, `<details>`, `<input type=...>` are accessible by default. Reach for `role=...` only when the platform genuinely doesn't fit.
3. **Color contrast is not in this skill.** Use a contrast tool or a design-token review for that — it requires computed-style information this skill can't reliably derive from source.
4. **Test with a keyboard.** The skill catches *patterns*; it doesn't simulate user interaction. Before claiming a fix, tab through the change.

## Why this exists

A11y violations are some of the most frequently flagged review issues *and* the most frequently shipped — because the failure modes are invisible to a mouse user with a sighted browser. The eight blocker patterns above are the ones that show up over and over: each one is a one-line fix, but only when caught at draft time.

A reviewer or bot catching A1 means the user has already shipped a button keyboard users can't reach. Catching it here means they never did.
