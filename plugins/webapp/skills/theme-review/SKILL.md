---
name: theme-review
description: "[pr-review-focus-area: Theming & Tokens] Review design token usage, dark/light mode implementation, and styling consistency."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Theme Review

Review code for correct usage of the project's design token system and theme implementation.

## Invocation

`/theme-review` — reviews changed files for theme and styling issues.

## Setup

Read `CLAUDE.md` to identify the project's design token system (CSS variables, theme config, token file locations).

## Checks

### Semantic Tokens over Hardcoded Values
- Flag hardcoded color values (`#fff`, `rgb(...)`, `hsl(...)`) in component styles. Use semantic tokens from the project's design system.
- Flag hardcoded spacing values where the project defines a spacing scale.
- Flag hardcoded font sizes, weights, or families where typography tokens exist.
- **Exception**: One-off values in global theme definition files are expected.

### Dark/Light Mode
- Theme switching must use CSS custom properties (variables), not conditional classes or JavaScript-based value swapping.
- Flag patterns like `isDark ? 'color-a' : 'color-b'` in component code.
- Flag theme-conditional class names (e.g., conditional dark mode utility classes such as `dark:` prefix classes) if the project uses CSS variable-based theming instead of utility-class dark mode.
- Verify all custom components respect the theme (no components that only look correct in one mode).

### Consistency
- All components in the same category should use the same token patterns.
- Flag mixed approaches (some components using tokens, others using raw values).
- Verify hover, focus, and active states use appropriate token variants.

### Accessibility
- Color contrast must meet WCAG AA (4.5:1 for normal text, 3:1 for large text).
- Flag color as the sole indicator of state (add icons, text, or patterns).
- Focus indicators must be visible in both light and dark modes.

## Report Format

List findings per file with the specific hardcoded value and the recommended token. Provide a summary count.
