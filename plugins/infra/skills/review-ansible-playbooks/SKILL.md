---
name: review-ansible-playbooks
description: "[pr-review-focus-area: Ansible Playbooks] Deeper Ansible role and playbook audit beyond ansible-lint — idempotency smells, handler misuse, secret handling, become-scope, tag discipline."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[role or playbook path]"
---

# Ansible Playbook Review

Audit Ansible roles and playbooks for anti-patterns that `ansible-lint`
does not catch — idempotency smells, handler misuse, unsafe secret
handling, overly broad `become:` scope, and undisciplined tag use. This
skill is strictly **read-only, repo-local** — it never SSHes to live
hosts, never executes playbooks against real inventory, and never applies
changes.

## Invocation

The user runs `/review-ansible-playbooks` with an optional path to a
single role (`roles/common`) or playbook (`playbooks/site.yml`). Without
an argument, scan every role and playbook discoverable under the
repository root.

## Execution Steps

For each step, report **PASS**, **FINDING**, or **SKIPPED** (nothing in
scope for that category).

### 1. Scope

Enumerate roles and playbooks under the argument path. Default globs when
no argument is given:

- `roles/*/tasks/*.yml`, `roles/*/handlers/*.yml`,
  `roles/*/defaults/*.yml`, `roles/*/vars/*.yml`,
  `roles/*/meta/main.yml`, `roles/*/templates/**/*.j2`
- `playbooks/**/*.yml`, `site.yml`, `*.ansible.yml`
- Collection roles under `collections/ansible_collections/*/*/roles/`
  when a `requirements.yml` or `galaxy.yml` is present

If no Ansible content is found, mark the run **SKIPPED** and stop.

### 2. Idempotency Smells

Grep task files for:

- `ansible.builtin.command:` or `ansible.builtin.shell:` (including short
  form `command:` / `shell:`) **without** any of `creates:`,
  `removes:`, `changed_when:`, or a comment justifying non-idempotency.
- `ansible.builtin.lineinfile:` applied to a file that is also managed by
  a nearby `template:` task — duplicate ownership.
- Repeated near-identical `file:` tasks that could collapse into a
  `template:` or `copy:` with a loop.
- `raw:` used outside bootstrap contexts (flag and require comment).
- `check_mode: false` used to hide a non-idempotent task — flag with the
  file:line and ask whether the logic can be rewritten idempotently.

### 3. Handler Misuse

- For each handler declared under `roles/*/handlers/main.yml`, grep the
  role's task files for matching `notify:` entries. Unused handler =
  FINDING.
- For each `notify:` entry in tasks, verify a handler of that exact name
  exists in the same role or is imported. Missing handler = FINDING.
- Handlers that themselves contain multi-step logic (more than one task
  of substantive work, or `block:` with several inner steps) should be
  promoted to a role or a tasks file included with `import_tasks:`.

### 4. Secret Handling

Grep for:

- Variables with name-stems `password`, `passwd`, `secret`, `token`,
  `api_key`, `apikey`, `private_key`, `passphrase` declared in plain
  `defaults/main.yml`, `vars/main.yml`, `group_vars/*.yml`, or
  `host_vars/*.yml` without a `$ANSIBLE_VAULT;` header.
- `lookup('env', '...')` used in contexts where the surrounding task
  lacks `no_log: true`.
- `hashi_vault`, `aws_ssm`, or `community.hashi_vault.vault_read_secret`
  lookups in tasks without `no_log: true`.
- Files named `vault.yml`, `secrets.yml`, or matching `*secret*.yml` that
  are **not** encrypted (first-line check for `$ANSIBLE_VAULT;`) and that
  appear in `git ls-files` (tracked).

Each hit is a **HIGH** FINDING.

### 5. Become Scope

- `become: yes` / `become: true` set at the play level when many tasks
  within do not require elevation — suggest moving `become:` onto the
  specific tasks that need it.
- `become_user:` omitted on an escalated task when root is not required
  (e.g. managing a service account's config).
- `become_method: su` without justification (prefer `sudo`).
- Nested `become:` contradictions between play, block, and task.

### 6. Tag Discipline

- Build a set of all tags declared via `tags:` on plays, roles, blocks,
  and tasks.
- Build a set of all tags referenced in documentation comments and
  playbook headers (`# Usage: ansible-playbook ... --tags foo`).
- Orphan tags (declared but never referenced in docs or CI) = FINDING.
- Tasks with no `tags:` in a playbook that otherwise uses tags heavily =
  FINDING.
- If the playbook header comment does not document the `--tags` contract
  and the playbook uses tags, FINDING.

### 7. Run ansible-lint (If Available)

Invoke `ansible-lint --nocolor` against the scoped path if the binary is
installed. Include its output in a dedicated subsection. Do **not**
replicate its rule checks in this skill's own findings — attribute each
ansible-lint hit to ansible-lint. If the binary is missing, mark the
subsection **SKIPPED**.

## Output Format

```
## Ansible Playbook Review — <path or repo root>

### Scope
Roles scanned: N
Playbooks scanned: N

### Findings by Role / Playbook

#### roles/common
- [FINDING] tasks/bootstrap.yml:14 — shell: without creates / changed_when
- [FINDING] handlers/main.yml — handler "restart app" declared, never notified
- [HIGH] vars/main.yml:3 — plain-text "api_token" (should be vaulted)

#### roles/nginx
- [FINDING] tasks/main.yml — play-level become: yes but 6 of 11 tasks do not require root
- [FINDING] tasks/main.yml — tasks missing tags while other tasks in the role are tagged

#### playbooks/site.yml
- [FINDING] header comment does not document --tags contract; tags "deploy", "config" referenced by tasks

### ansible-lint Output
<captured output, or SKIPPED: ansible-lint not installed>

**Totals:** FINDING: N, HIGH: N
**Verdict:** <PASS | CONCERN | FAIL>
```

## Verdict

- **PASS**: zero FINDINGs across all categories.
- **CONCERN**: one or more FINDINGs, no HIGH severity.
- **FAIL**: one or more HIGH findings (plain-text secret in tracked file,
  secret lookup without `no_log:`, unencrypted `vault.yml` / `secrets.yml`
  tracked in git).
- **SKIPPED**: no Ansible content in scope.

## Rules

1. **Read-only, repo-local.** Never SSH. Never run `ansible-playbook`
   without `--check`. Never run `ansible` ad-hoc commands. Allowed
   commands: `ansible-inventory --list`, `ansible-lint`,
   `ansible-playbook --check --diff`. Nothing else.
2. **No mutation.** Do not propose `ansible-playbook ...` without
   `--check`. Do not propose `ssh`, `rsync`, or `scp`.
3. **No fabrication.** Do not invent role names, host names, tag names,
   or task contents. If scope is empty, mark SKIPPED rather than
   guessing.
4. **Attribute ansible-lint findings to ansible-lint.** Keep this skill's
   own output focused on the higher-level smells the linter misses.
5. **Graceful SKIPPED.** Missing `ansible-lint`, missing inventory, or
   empty scope each degrade to SKIPPED for the relevant step.
6. **Report, do not fix.** Surface findings; never auto-edit roles or
   playbooks.

$ARGUMENTS
