---
name: infra-inventory
description: Print a concise inventory of IaC artifacts and cloud auth status for the current repo
---

Report the current repo's infrastructure surface and available cloud credentials. This is a **read-only** pre-flight intended to be run before any `/review-*` or `/triage-*` skill.

## Instructions

When this command is invoked, follow these steps exactly:

1. **Run the scope detector:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/detect-iac-scope.sh
   ```
   If `CLAUDE_PLUGIN_ROOT` is not set (e.g., running from the plugin dev repo directly), fall back to `plugins/infra/scripts/detect-iac-scope.sh`.

2. **Run the cloud auth probe:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh all
   ```
   Same fallback as above.

3. **Format the output** as two sections:

### IaC surface

Produce a compact table with only the categories that are `present: true`:

```
| Category        | Count | Sample paths (up to 3)                       |
|-----------------|-------|----------------------------------------------|
| Terraform       | N     | path/a, path/b, path/c                       |
| Ansible roles   | N     | ...                                          |
| Kubernetes      | N     | ...                                          |
| Helm charts     | N     | ...                                          |
| Docker Compose  | N     | ...                                          |
```

Skip any category with no findings. If nothing is present, say so explicitly: `No IaC artifacts detected in this repo.`

### Cloud auth

One line per provider, in this format:

```
- **AWS** — OK / UNAUTHENTICATED / EXPIRED / MISSING_CLI  ·  identity: <arn-or-null>
- **GCP** — ...
- **kubectl** — ...
```

If a provider is `MISSING_CLI`, note that the corresponding review skills (`review-aws-*`, `review-gcp-*`, `review-gke`, `review-kubernetes-rbac`) will SKIP live-account checks but may still review IaC.

### Suggested next steps

Based on the surface detected, suggest one or two relevant skills to run next. Examples:

- Terraform detected, AWS OK → `/review-drift` or `/assess-change-risk`
- Ansible roles detected → `/review-ansible-playbooks`, `/review-linux-hardening`
- Kubernetes detected, kubectl OK → `/review-kubernetes-rbac`
- Vulnerability scanner reports present under `security/` or `reports/` → `/triage-vulnerabilities`

Keep suggestions specific to what was actually detected. Do not list every available skill.

## Rules

- Do not run any mutating commands. This command only reads.
- Do not fabricate counts, paths, or identities — only report what the two scripts returned.
- If either script fails (non-zero exit), report the error and skip that section rather than inventing output.
