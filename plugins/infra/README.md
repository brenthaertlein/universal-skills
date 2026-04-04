# Infra — Infrastructure & DevOps Skills

Skills for infrastructure-as-code projects. Validates Terraform, Ansible, Kubernetes, Helm, and Docker Compose configurations.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| preflight | `/preflight` | IaC quality gate — validates all infrastructure tools |
| security-audit | `/security-audit` | Scan for secrets, PII, and sensitive data |
| suggest | `/suggest` | Recommend self-hosted services and infrastructure additions |

## Supported Tools

The preflight skill auto-detects and validates:

- **Terraform** — `terraform fmt -check`, `terraform validate`
- **Ansible** — `ansible-lint`, `ansible-inventory` validation
- **Kubernetes** — `kubectl kustomize` dry render
- **Helm** — `helm lint` on charts
- **Docker Compose** — `docker compose config` validation
- **YAML** — Syntax validation for all `.yml`/`.yaml` files

Missing tools are skipped gracefully — never treated as failures.

## Setup

Run `/setup` to automatically configure recommended permissions, or manually add to `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
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
  }
}
```

Operations that modify infrastructure (terraform apply, kubectl apply, helm upgrade, ansible-playbook) are intentionally excluded — you'll be prompted for approval each time.

## Companion Plugins

### Sibling plugins (same repo)

| Plugin | What it adds |
|--------|-------------|
| **core** (recommended) | Commit workflows, PR management, planning, debugging. `core/commit` runs infra preflight checks automatically when this plugin is installed. |
| **webapp** | Not typically used alongside infra, but no conflicts if both are installed. |

### Public plugins

| Plugin | Integration |
|--------|-------------|
| **superpowers** | `brainstorming` before new infrastructure design. `systematic-debugging` for infrastructure issues. `verification-before-completion` to ensure changes are validated before claiming done. |
| **code-simplifier** | Autonomous refinement of Ansible playbooks, Terraform modules, and other IaC files after editing. |
