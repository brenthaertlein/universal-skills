---
name: setup
description: Configure recommended permissions for the infra plugin
---

Configure recommended permissions for the infra plugin by merging them into `.claude/settings.json`.

## Recommended Permissions

The following permissions should be added to `.claude/settings.json` under `permissions.allow`:

```json
[
  "Bash(terraform fmt -check*)",
  "Bash(terraform validate*)",
  "Bash(terraform plan*)",
  "Bash(ansible-lint*)",
  "Bash(ansible-inventory*)",
  "Bash(kubectl get*)",
  "Bash(kubectl describe*)",
  "Bash(kubectl kustomize*)",
  "Bash(helm lint*)",
  "Bash(helm list*)",
  "Bash(helm show*)",
  "Bash(docker compose config*)",
  "Bash(python3 -c \"import yaml*)"
]
```

> **Note:** Only read-only and validation operations are auto-allowed. Mutating operations (terraform apply, kubectl apply, helm upgrade, ansible-playbook) will always prompt for approval.

## Instructions

When this command is invoked, follow these steps exactly:

1. **Read** `.claude/settings.json` if it exists. If it does not exist, start with an empty object `{}`.
2. **Parse** the JSON. Extract the existing `permissions.allow` array. If `permissions` or `permissions.allow` does not exist, treat it as an empty array.
3. **Merge** the recommended permissions listed above into the existing `permissions.allow` array. Do NOT add duplicates -- skip any permission that already exists in the array.
4. **Write** the updated JSON back to `.claude/settings.json`, preserving all other existing keys and values in the file. Use 2-space indentation for readability.
5. **Report** the result to the user: "Added N permissions for infra plugin. Existing permissions preserved." where N is the number of new permissions that were actually added (not already present). If all permissions were already present, say "All infra plugin permissions already configured. No changes needed."
