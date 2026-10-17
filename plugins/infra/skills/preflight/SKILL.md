---
name: preflight
description: "IaC quality gate \u2014 validates Terraform, Ansible, Kubernetes, Helm, Docker Compose, and YAML without committing."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
---

# IaC Preflight Check

Validate infrastructure-as-code changes without committing. This is a **read-only** quality gate.

## Invocation

The user runs `/preflight` to validate all IaC files changed on the current branch — committed, uncommitted, and untracked.

## Execution Steps

Run checks in the following order. For each check, report **PASS**, **FAIL**, **SKIPPED** (tool not installed), or **N/A** (no matching files changed).

### 1. Scope Detection

Identify every file changed on this branch: changes already committed relative to the base branch, plus uncommitted and untracked changes in the working tree. A working-tree-only scope sees nothing once the work is committed, which is exactly when a branch is preflighted before opening a PR.

**Resolve the base branch.** Use the repository's default branch, the first of these that resolves:

1. `git rev-parse --abbrev-ref --verify --quiet origin/HEAD` (e.g. `origin/main`; prints nothing if unset)
2. `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` → use `origin/<name>` if `git rev-parse --verify --quiet origin/<name>` succeeds, otherwise the local `<name>`
3. A local `main`, then `master` (`git rev-parse --verify --quiet <name>`)

Do not use `@{upstream}`: once the branch is pushed, its upstream is the branch itself, and diffing against it hides every pushed commit. If nothing resolves (no remote, base branch absent), continue in **working-tree-only** mode rather than erroring.

**Collect changed files.** Run each command separately:

- `git diff --name-only HEAD` — staged and unstaged changes to tracked files. If the repository has no commits yet, use `git diff --cached --name-only` and `git diff --name-only` instead.
- `git diff --name-only <base>...HEAD` — changes committed on this branch since it diverged from the base. Skip in working-tree-only mode.
- `git status --porcelain --untracked-files=all` — keep only the `??` (untracked) entries.

Union the results, de-duplicate, and drop paths that no longer exist on disk (deleted files cannot be validated).

**If the set is empty**, report `No changes detected (base: <base>)` — or `(working tree only — no base branch resolved)` — and stop. Do not run the remaining checks just to mark them N/A.

Categorize the changed files into areas:

| Area             | File patterns                                                    |
| ---------------- | ---------------------------------------------------------------- |
| **terraform**    | `*.tf`, `*.tfvars`, `*.tfvars.json`                              |
| **ansible**      | `**/playbooks/**`, `**/roles/**`, `**/inventory/**`, `*.ansible.yml` |
| **kubernetes**   | `**/k8s/**`, `**/kustomize/**`, `kustomization.yaml`            |
| **helm**         | `**/charts/**`, `Chart.yaml`, `values.yaml`                     |
| **docker-compose** | `docker-compose*.yml`, `docker-compose*.yaml`, `compose*.yml` |
| **scripts**      | `*.sh`, `*.bash`                                                |
| **docs**         | `*.md`, `*.txt`, `*.rst`                                        |
| **config**       | `*.yml`, `*.yaml`, `*.json`, `*.toml`, `*.ini`                  |

Auto-detect paths by scanning the repository structure. Do not assume any fixed directory layout.

Report: the base branch used (or that the scope is working-tree-only), then each area with the number of changed files.

### 2. YAML Lint

Validate syntax for all changed `.yml` and `.yaml` files.

- Use `yamllint` if available, otherwise parse with `python3 -c "import yaml; yaml.safe_load(open('...'))"` or equivalent.
- Report each file as valid or invalid with line/column of first error.

### 3. Terraform

Skip if no `.tf` files changed.

1. **Format check**: Run `terraform fmt -check -diff` on changed `.tf` files.
2. **Validate**: For each Terraform environment/module directory containing changed files, run `terraform validate` only if the directory has been initialized (`.terraform/` exists). If not initialized, report SKIPPED for that directory.

Do NOT run `terraform init`, `terraform plan`, or `terraform apply`.

### 4. Ansible

Skip if no Ansible files changed.

1. **ansible-lint**: Run `ansible-lint` on changed playbooks and roles. If `ansible-lint` is not installed, SKIP.
2. **Inventory validation**: Run `ansible-inventory --list` on any changed inventory files to verify syntax. If `ansible-inventory` is not installed, SKIP.

### 5. Kubernetes / Kustomize

Skip if no Kubernetes manifests changed.

1. **Kustomize render**: For directories containing `kustomization.yaml`, run `kubectl kustomize <dir>` as a dry render. Verify it produces valid output without errors.
2. **Manifest validation**: If `kubectl` is available, use `kubectl apply --dry-run=client -f <file>` on changed manifests (outside kustomize directories).

### 6. Helm

Skip if no Helm chart files changed.

1. **Helm lint**: For each chart directory containing changed files, run `helm lint <chart-dir>`.
2. If `helm` is not installed, SKIP.

### 7. Docker Compose

Skip if no Docker Compose files changed.

1. Run `docker compose -f <file> config --quiet` on each changed compose file.
2. If `docker compose` is not available, try `docker-compose config --quiet`.
3. If neither is available, SKIP.

## Summary Format

```
## Preflight Summary

| Check            | Status   | Details              |
| ---------------- | -------- | -------------------- |
| Scope Detection  | PASS     | 12 files in 3 areas (base: origin/main) |
| YAML Lint        | PASS     | 4/4 files valid      |
| Terraform        | FAIL     | fmt: 2 files need formatting |
| Ansible          | SKIPPED  | ansible-lint not installed |
| Kubernetes       | N/A      | no k8s files changed |
| Helm             | N/A      | no chart files changed |
| Docker Compose   | PASS     | 1/1 files valid      |

**Verdict: NO-GO** (1 failure)
```

Verdict rules:
- **GO**: All checks PASS, SKIPPED, or N/A
- **NO-GO**: Any check is FAIL

## Rules

1. **Read-only**: Never modify any file. Never run `terraform apply`, `ansible-playbook`, `kubectl apply` (without `--dry-run`), or any destructive command.
2. **Skip gracefully**: If a required tool is not installed, mark the check as SKIPPED and continue. Never fail the entire preflight because a tool is missing.
3. **Never auto-fix**: Report problems but do not fix them. The user decides what to fix.
4. **Auto-detect paths**: Scan the repository to find IaC files. Do not assume any hardcoded directory structure.
