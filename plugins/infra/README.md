# Infra — Enterprise Infrastructure & DevOps Skills

Skills for sysadmins, DevOps engineers, and SREs operating across AWS, GCP, Kubernetes, and baremetal/on-prem. Covers IaC validation, drift/cost/vulnerability triage, cloud IAM and Well-Architected reviews, postmortems and runbooks, and baremetal hardening.

All skills are **read-only**. Mutating operations (terraform apply, kubectl apply, helm upgrade, ansible-playbook without `--check`, AWS/GCP write calls) are intentionally excluded — you will be prompted for approval each time.

## Skills

### Foundations

| Skill / Command | Invocation | Description |
|-----------------|------------|-------------|
| preflight | `/preflight` | IaC quality gate — validates Terraform, Ansible, Kubernetes, Helm, Docker Compose, YAML |
| security-audit | `/security-audit` | Scan for secrets, PII, and sensitive data before committing |
| suggest | `/suggest` | Recommend self-hosted services and infrastructure additions |
| infra-inventory | `/infra-inventory` | Pre-flight: print IaC artifacts and cloud auth status for the current repo |

### Cross-cutting (cloud-agnostic)

| Skill | Command | Description |
|-------|---------|-------------|
| review-drift | `/review-drift` | Compare Terraform/Pulumi state to live cloud reality |
| review-costs | `/review-costs` | Cost hotspot audit across IaC + cloud inventory |
| triage-vulnerabilities | `/triage-vulnerabilities` | Rank CVE/SBOM scanner findings by fixability and exposure |
| draft-postmortem | `/draft-postmortem` | Blameless postmortem draft from timeline evidence |
| draft-runbook | `/draft-runbook` | Generate or refresh a service runbook |
| review-observability | `/review-observability` | Audit log/metric/trace coverage for a service |
| assess-change-risk | `/assess-change-risk` | Blast-radius assessment for a pending IaC change |
| review-disaster-recovery | `/review-disaster-recovery` | DR readiness audit (RTO/RPO, backups, failover) |

### AWS

| Skill | Command | Description |
|-------|---------|-------------|
| review-aws-iam | `/review-aws-iam` | IAM least-privilege audit for roles, policies, and users |
| review-aws-well-architected | `/review-aws-well-architected` | Lightweight Well-Architected Framework review (5 pillars) |
| review-aws-tagging | `/review-aws-tagging` | Org-taxonomy tag compliance audit |
| triage-aws-security-findings | `/triage-aws-security-findings` | Consolidate Security Hub + GuardDuty + Inspector + Trusted Advisor |

### GCP

| Skill | Command | Description |
|-------|---------|-------------|
| review-gcp-iam | `/review-gcp-iam` | GCP IAM audit including SA impersonation paths |
| triage-gcp-recommender | `/triage-gcp-recommender` | Recommender API findings ranked by $/risk impact |
| review-gke | `/review-gke` | GKE cluster hardening and cost review |

### Kubernetes

| Skill | Command | Description |
|-------|---------|-------------|
| review-kubernetes-rbac | `/review-kubernetes-rbac` | RBAC audit across EKS/GKE/AKS/on-prem |

### Baremetal / on-prem

Baremetal skills read Ansible inventory, roles, playbooks, and fact caches from the repo. They do **not** SSH to live hosts.

| Skill | Command | Description |
|-------|---------|-------------|
| review-linux-hardening | `/review-linux-hardening` | CIS-benchmark-lite audit via declared Ansible state |
| review-systemd-units | `/review-systemd-units` | systemd unit audit (Restart, limits, sandboxing) |
| review-ansible-playbooks | `/review-ansible-playbooks` | Role/playbook audit beyond `ansible-lint` |
| triage-hardware-health | `/triage-hardware-health` | SMART / RAID / firmware triage from collected facts |

## Agents

| Agent | Description |
|-------|-------------|
| `principal-sre` | Principal-level sysadmin / DevOps / SRE reviewer. Dispatch via `Agent({subagent_type: "principal-sre"})` from skills needing senior production scrutiny (blast radius, postmortems, DR readiness, runbook reviews). Also invocable by the user via `/agents`. |
| `appsec-engineer` | Principal-level application & cloud security engineer. Dispatch via `Agent({subagent_type: "appsec-engineer"})` from skills needing adversarial security scrutiny — exploitability triage, blast radius of a compromised credential, real risk versus checkbox noise. Also invocable directly via `/agents`. |

### How skills use the agents

Skills that benefit from principal-level reasoning should dispatch to an agent when:

- The decision is architectural, not line-level (e.g., "is this DR plan actually tested?")
- Evidence needs synthesis across multiple sources (logs, alerts, deploy history)
- A verdict requires production-operator or security judgment, not just a checklist

`principal-sre` examples: `draft-postmortem`, `assess-change-risk`, `review-disaster-recovery`, `review-observability`.
`appsec-engineer` examples: `security-audit` (rank findings by exploitability), `triage-vulnerabilities` (sanity-check reachability without re-scoring).

Skills stay in charge of the output format; the agent provides the reasoning lens.

## Helper scripts

Reusable bash helpers under `plugins/infra/scripts/` — invoked by skills and by `/infra-inventory`.

| Script | Output | Consumers |
|--------|--------|-----------|
| `detect-iac-scope.sh` | JSON describing Terraform / Pulumi / CFN / Ansible / K8s / Helm / Compose artifacts in the repo | `preflight`, `review-drift`, `review-costs`, `assess-change-risk`, `/infra-inventory` |
| `cloud-auth-check.sh {aws\|gcp\|kubectl\|all}` | JSON probing CLI auth status (`OK`/`MISSING_CLI`/`UNAUTHENTICATED`/`EXPIRED`) | all cloud skills (`review-aws-*`, `review-gcp-*`, `review-gke`, `review-kubernetes-rbac`), `/infra-inventory` |

Scripts are read-only — they probe, they don't mutate.

## Hooks

`hooks/hooks.json` adds four `PreToolUse` Bash-matcher nudges:

1. **`git commit`** — reminds to run `/security-audit`, plus `/preflight` and `/assess-change-risk` when IaC files are staged.
2. **`terraform apply|destroy`** — safeguard: prompts to confirm `/assess-change-risk` and `/review-drift` were run.
3. **`kubectl apply|delete|patch|replace|scale|rollout`** — safeguard: prompts to confirm the target context.
4. **`ansible-playbook`** without `--check` — safeguard: prompts to rehearse in check mode first.

## Supported Tools

The preflight skill auto-detects and validates:

- **Terraform** — `terraform fmt -check`, `terraform validate`
- **Ansible** — `ansible-lint`, `ansible-inventory` validation
- **Kubernetes** — `kubectl kustomize` dry render
- **Helm** — `helm lint` on charts
- **Docker Compose** — `docker compose config` validation
- **YAML** — Syntax validation for all `.yml`/`.yaml` files

Missing tools (and missing cloud credentials) are skipped gracefully — never treated as failures.

## Setup

Run **`/onboard`** (from the core plugin) to configure recommended permissions for infra along
with any other installed universal-skills plugins in one guided flow. Prefer to do it by hand?
The canonical read-only allow-list is the `balanced` tier of [`onboard-presets.json`](onboard-presets.json) — copy its `allow` entries into `.claude/settings.json`. It includes read-only permissions for:

- **IaC** — `terraform`, `pulumi`, `ansible-lint`, `ansible-inventory`, `ansible-playbook --check --diff`, `kubectl get/describe/diff`, `helm lint/list/show`, `docker compose config`
- **AWS** — `aws ec2/iam/s3api/rds/elbv2/cloudformation/backup describe-* | get-* | list-*`, `aws securityhub/guardduty/inspector2 get-findings | list-findings`, `aws resourcegroupstaggingapi get-resources`, `aws accessanalyzer list-findings`, `aws support describe-trusted-advisor-checks`
- **GCP** — `gcloud projects/folders/organizations get-iam-policy`, `gcloud compute instances/disks list`, `gcloud recommender recommendations list`, `gcloud container clusters describe/list`, `gcloud iam service-accounts list`
- **Kubernetes RBAC** — `kubectl get clusterroles/roles/clusterrolebindings/rolebindings/serviceaccounts`
- **Baremetal** — `smartctl`, `mdadm --detail`, `zpool status/list`, `ipmitool sel list`, `dmidecode`

Mutating operations (`terraform apply`, `kubectl apply`, `helm upgrade`, `ansible-playbook` without `--check`, any AWS/GCP `create/update/delete/put`, `set-iam-policy`, `add-iam-policy-binding`) are intentionally excluded — you will be prompted for approval each time.

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
