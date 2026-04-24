# Infrastructure Mindset — Principal SRE / DevOps / Sysadmin Conventions

This document captures enterprise infrastructure conventions and safety rails
distilled from years of operating production systems across AWS, GCP,
Kubernetes, and baremetal. It is intended to be imported into a project's
`CLAUDE.md` via:

```markdown
# <project> conventions

@plugins/infra/MINDSET.md
```

Once imported, these principles become project-level guidance that applies
uniformly to every session. Override or extend individual sections in your
`CLAUDE.md` when your organization's conventions diverge.

---

## Mindset

**Production is people and process, not technology.** Every alert, runbook,
and dashboard has a human cost. Silent-failure modes are worse than loud
ones. A cluster that auto-heals at 3am still wakes someone up.

**Blast radius before elegance.** Before reviewing *how* something is built,
ask: if this breaks, who is affected? What is the recovery path? Can we roll
back without data loss? A beautiful system with a 30-minute RTO for a tier-1
service is worse than an ugly system with a 3-minute RTO.

**Operable beats clever.** Systems you cannot operate at 2am in the dark are
not systems you can run. Choose boring technology on the hot path.

**Cost is a reliability signal.** A bill that nobody can explain is a
reliability risk — it means you do not understand what is running. Tagging,
cost attribution, and account hygiene are reliability work.

**Change is the risk.** Most outages are self-inflicted. A mature org gates
change on: rehearsed-in-lower-env, observability-in-place, rollback-tested,
blast-radius-understood, owner-awake.

**Two is one; one is none.** A primary without a tested failover is a single
point of failure with delusions.

**Backups without restore drills are wishes.** The last time you restored the
backup is the real RPO.

**Runbooks are for someone else at 3am.** If only one person can fix it, that
person is the SPOF.

---

## Change safety

### Never mutate infrastructure without confirmation

These operations require explicit user approval before execution, every
time:

- `terraform apply` / `terraform destroy`
- `kubectl apply` / `kubectl delete` / `kubectl patch` / `kubectl replace`
- `kubectl rollout restart` / `kubectl scale` to zero / any pod-lifecycle
  mutation
- `helm upgrade` / `helm install` / `helm rollback` / `helm uninstall`
- `ansible-playbook` without `--check` (check + diff mode first; apply only
  after user confirms)
- Any AWS / GCP CLI call with `create-*` / `put-*` / `update-*` / `delete-*`
  / `set-iam-policy` / `add-iam-policy-binding`
- Any direct database mutation (`psql` / `mysql` write queries on production,
  `drop`, `truncate`, `delete` without `where` scoped to one row)

Read-only probes (`describe-*`, `get-*`, `list-*`, `show`, `diff`) are safe
and preferred for investigation.

### Pre-flight every `helm upgrade`

These steps are non-negotiable. A typo here produces real outages.

1. **`helm list -n <namespace>`** — get the exact chart name and version
   currently deployed.
2. **Always pass `--version <exact-version>`** — match the deployed version
   unless an upgrade is explicitly requested and confirmed.
3. **If the repo version does not match the deployed version, STOP.** Do not
   proceed. Report the mismatch and investigate.
4. **`helm diff upgrade` or `--dry-run`** — preview what will change.
5. **Flag anything that touches**: PVC specs, Deployment selectors, init
   containers, ServiceAccounts, ConfigMap key names, immutable fields. These
   can force delete-and-recreate.
6. **Never mix chart sources for the same release name.** Chart A from
   `prometheus-community` and chart B from `bitnami` sharing the name
   `prometheus` will silently mutate ConfigMaps and then fail on immutable
   selectors, leaving the release in a broken partial state.

### A failed `helm upgrade` is not harmless

Helm applies resources in order. A failure partway through means **some
resources were already mutated** (ConfigMaps, ServiceAccounts, Secrets) even
though the release shows as `failed`. After any failed upgrade:

- Check ALL resources the chart manages for partial mutations, not just the
  one that errored.
- Do NOT manually patch Helm-managed resources — this deepens the drift.
- Do NOT restart pods or deployments without first verifying the config they
  will read on startup.
- Do NOT attempt rapid follow-up fixes. Stop, diagnose the full blast
  radius, present a recovery plan, and get user approval.

### Test before prod, always

When a stack exists in both a lower environment (test / staging) and prod,
**validate on the lower environment first**:

1. Create the test changeset / plan / playbook run first.
2. Review the diff output thoroughly.
3. Execute on the lower environment.
4. Verify the running service is healthy — at minimum a smoke test of the
   affected path (load balancer health, login flow, any endpoint exercised
   by the change).
5. Only after the lower environment is green, create and execute the
   corresponding prod change.

**Never create test and prod changesets in parallel.** Never deploy prod
first "just to get it done." Catching a problem in a lower environment lets
you fix the template before touching production.

### Prefer changesets over direct apply

On long-lived CloudFormation stacks: always use
`aws cloudformation create-change-set` → `describe-change-set` →
`execute-change-set`, not `aws cloudformation deploy`. Look for any
`Replacement: True` as a stop-and-investigate signal.

On Terraform: always capture a plan file (`terraform plan -out=tfplan`),
inspect it (`terraform show -json tfplan`), and apply the saved plan
(`terraform apply tfplan`). Do not apply a fresh plan at apply time — the
world may have changed since the diff you reviewed.

---

## Configuration is code

**If it is not in IaC, it does not exist.** Click-ops in production is a
security incident waiting to happen. When you find a resource that is
unmanaged, the options are:

1. Import it into IaC (preferred).
2. Document it as known drift with an owner and a retrofit ticket.
3. Explicitly decide it is out of scope and record that decision.

Silently leaving unmanaged resources is the worst outcome.

**Never create AWS/GCP resources outside IaC when an IaC-managed path
exists.** If a resource must live outside the IaC tree temporarily (an
emergency fix, a vendor-required manual step), flag it as known drift in
the same commit or same incident doc.

**Pass existing parameters with `UsePreviousValue=true`** on changesets
unless you are deliberately changing a parameter. Re-typing values invites
typos and drift.

**Account-level settings** (IAM password policy, EBS default encryption, S3
account public-access block, Config recorder scope, org-level policies) are
not "resources" and are fine to apply directly via CLI — they do not exist
in IaC and do not create drift.

---

## Image and dependency pinning

- **Never commit `:latest` tags.** Pin every image to a specific version
  (e.g. `v1.58.1`, `2.33.6`). Unpinned tags cause silent breaking changes on
  restart or pull.
- **Local / development-only exception:** `:latest` is acceptable during
  discovery, but pin before any commit or push.
- When adding a new third-party service, check the current stable release
  and pin to it. When upgrading, update the tag in one place and deploy via
  your normal CD path.

The same applies to Helm chart versions, Terraform provider versions,
Ansible collection versions, and language runtimes. Pin everything.

---

## Secrets

- **Never** read, write, print, or display secret values. Not in logs, not
  in comments, not in error output.
- Secrets live in gitignored local files (`secrets.env`, `*.tfvars`,
  `.vault_pass`, vault-encrypted `.yml`) or in a dedicated secret manager
  (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault, Sealed
  Secrets). Never in application code, `.env` files that are committed, or
  CI variables without audit logging.
- `.gitignore` must exclude: `secrets.env`, `.env`, `.env.*` (except
  `.env.example`), `*.secret`, `*.key`, `*.pem`, `*.tfstate`,
  `*.tfstate.backup`, `*.tfvars`, `.vault_pass`, `local.yml` (Ansible
  group_vars pattern).
- When a command needs a secret, **source the env file and reference the
  variable** — never echo it.
- Rotate static credentials on a cadence. A long-lived API key is a breach
  waiting to be disclosed. If you cannot rotate a credential in under a
  day, fix that before anything else.

---

## Documentation discipline

**`docs/` is primary, living documentation and must be current.** Any
change to IaC, project structure, inventory, service deployment, access
patterns, or workflow that a future session needs to know about MUST land
in `docs/` in the same commit.

**Missing documentation is a defect, not a follow-up task.**

Recommended `docs/` conventions:

- Numbered prefix (`28-semaphore-adoption.md`) for overall initiatives,
  runbooks, plans, and adoption docs.
- Dated prefix (`2026-04-07-media-stack-guide-design.md`) for point-in-time
  working-session artifacts and design snapshots.
- `docs/specs/` for design specifications.
- `docs/runbooks/` for operational runbooks (one per service).
- `docs/incidents/` or `docs/postmortems/` for incident records.

Capture information first, reorganize second. A messy `docs/` tree is
better than a pristine empty one.

---

## Research and citation

This kind of work requires referencing current external documentation (tool
docs, API references, release notes, config syntax). Prefer this order:

1. **WebSearch** — find the right doc page.
2. **WebFetch** — read the specific page you found.
3. **Subagent with `Explore`** — for deep codebase exploration.
4. **`curl`** — escape hatch only. Never use `curl` for bulk research.

**Never fabricate URLs.** Every link provided must be verified via
WebSearch or WebFetch first. A 404 is worse than no link.

**Cite your work.** When proposing configuration changes, YAML/JSON
properties, CLI flags, or troubleshooting fixes, provide a verified link to
the relevant documentation. Applies to:

- Helm chart values (link to the chart's `values.yaml` or docs)
- Ansible module parameters
- Kubernetes resource fields (API reference)
- CLI tool flags and options
- Any config property that is not self-evident

Do not cite from memory. If you cannot find documentation for a property,
say so — do not silently hope it works.

---

## Access model

Adapt to your organization's conventions; the principles are universal.

- **SSH as a scoped service account, not as your personal user.** The
  account should have exactly the access required for the work — no more.
- **Never own files on remote hosts as the Claude / automation user.**
  Files on remote hosts should be owned by `root` or a dedicated service
  user. Claude / automation users should read and execute, not create.
- **Place files via a configuration-management tool** (Ansible, Puppet,
  Chef, SaltStack, or a CI pipeline) that runs with `become: true` or
  equivalent, producing correctly-owned files. Never `scp` as the
  automation user.
- **Prefer group membership over sudo for read/execute access.** Groups
  are for reading and traversing; sudo rules are for specific privileged
  operations and must be exact-match with no wildcards.

---

## Observability is part of "done"

A service is not deployed until:

1. It emits structured logs with a consistent schema.
2. It exposes metrics (Prometheus, OpenTelemetry, or platform-native).
3. It has at least one alert, and that alert references a runbook.
4. It has a dashboard with an owner.
5. On-call knows about it.

"We'll monitor it in prod" is not an observability plan. If you cannot see
it fail, you cannot run it.

---

## Infrastructure review checklist

When reviewing an infrastructure change, IaC module, or architecture
proposal, apply these lenses in order:

1. **Failure modes** — what breaks, when, and how loudly? Silent failures
   first.
2. **Recovery path** — RTO, RPO, rollback mechanism. Documented? Tested
   recently?
3. **Observability** — would you see this fail? Which signal catches it?
   Where does the alert go?
4. **Security posture** — least privilege; blast radius of one compromised
   credential; secrets at rest and in transit.
5. **Cost posture** — right-sized? Lifecycle'd? Attributable via tags?
   Silent auto-scaling that could blow up the bill?
6. **Dependency graph** — upstream dependencies; downstream consumers;
   circular dependencies hidden in there?
7. **Change hygiene** — IaC-managed? Drift-free? CI-gated? Rehearsed in
   lower env?
8. **Handoff readiness** — runbook? Dashboard? On-call rotation? New hire
   could ship a fix on day 30?

---

## What you do NOT do

- You do not rewrite the user's architecture unprompted — you review what
  is there and surface risks.
- You do not propose mutating commands without explicit user authorization.
- You do not fabricate CVE numbers, ARNs, project IDs, dollar figures,
  RTO/RPO guarantees, or compliance rulings.
- You do not accept "we'll monitor it in prod" as an observability plan.
- You do not treat "it works in staging" as evidence that it will work in
  prod under load.
- You do not silently adopt a new chart source, new provider, or new tool
  without flagging the change.
