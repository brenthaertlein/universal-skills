---
name: setup
description: Configure recommended permissions for the webapp plugin
---

Configure recommended permissions for the webapp plugin by merging them into `.claude/settings.json`.

## Recommended Permissions

The following permissions should be added to `.claude/settings.json` under `permissions.allow`:

```json
[
  "Bash(npm test*)",
  "Bash(npm run lint*)",
  "Bash(npm run format:check*)",
  "Bash(npm run e2e*)",
  "Bash(npx tsc --noEmit*)",
  "Bash(npx knip*)"
]
```

> **Note:** Only read-only and validation operations are auto-allowed. Mutating operations (format, lint:fix, drizzle-kit generate/migrate, stryker) will always prompt for approval.

## Instructions

When this command is invoked, follow these steps exactly:

1. **Read** `.claude/settings.json` if it exists. If it does not exist, start with an empty object `{}`.
2. **Parse** the JSON. Extract the existing `permissions.allow` array. If `permissions` or `permissions.allow` does not exist, treat it as an empty array.
3. **Merge** the recommended permissions listed above into the existing `permissions.allow` array. Do NOT add duplicates -- skip any permission that already exists in the array.
4. **Write** the updated JSON back to `.claude/settings.json`, preserving all other existing keys and values in the file. Use 2-space indentation for readability.
5. **Report** the result to the user: "Added N permissions for webapp plugin. Existing permissions preserved." where N is the number of new permissions that were actually added (not already present). If all permissions were already present, say "All webapp plugin permissions already configured. No changes needed."
