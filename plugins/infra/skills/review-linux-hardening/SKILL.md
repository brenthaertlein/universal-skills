---
name: review-linux-hardening
description: "Lightweight CIS-benchmark-style audit of Linux host configuration as declared in Ansible inventory / roles / playbooks. Read-only, repo-local."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Agent
argument-hint: "[inventory-group or role path]"
---

# Linux Hardening Review

Audit Linux host hardening posture by statically analyzing the Ansible
inventory, roles, playbooks, templates, and any fact cache committed to the
repository. Cross-reference declared tasks against a CIS-benchmark-lite
control set and surface gaps per host group. This skill is strictly
**read-only, repo-local** — it never SSHes to live hosts and never executes
configuration changes.

## Invocation

The user runs `/review-linux-hardening` with an optional argument pointing at
a specific Ansible inventory group (e.g. `web_servers`) or a role path
(e.g. `roles/common`). Without an argument, audit every group discoverable
from the default inventory.

## Execution Steps

For each step, report **PASS**, **FINDING**, **SKIPPED** (prerequisite
missing), or **N/A** (nothing in scope).

### 1. Parse Ansible Inventory

Locate inventory under `inventory/`, `inventories/`, `hosts`, `hosts.ini`,
`hosts.yml`, or whatever path is declared in `ansible.cfg`. Run
`ansible-inventory --list --yaml` to resolve groups, group_vars, and
host_vars. If no inventory file is discoverable or `ansible-inventory` is
not installed, mark the run **SKIPPED** with the reason and stop.

Do not SSH. Do not invoke `ansible` ad-hoc modules. Do not run
`ansible-playbook` without `--check`.

### 2. Map Roles to Host Groups

For each host group in scope, enumerate the roles that target it by
inspecting `site.yml`, `playbooks/*.yml`, and any `import_playbook` /
`include_role` / `roles:` block. Build a group-to-role matrix. Glob
candidates: `playbooks/**/*.yml`, `roles/*/tasks/*.yml`,
`roles/*/handlers/*.yml`, `roles/*/defaults/*.yml`,
`roles/*/templates/**/*.j2`.

### 3. Run CIS-Lite Controls Across Roles

For every (group, role) pair, grep tasks, defaults, and templates for
declarations covering the following controls. Missing coverage = FINDING.

- **SSH daemon (`/etc/ssh/sshd_config`)**: `PermitRootLogin no`,
  `PasswordAuthentication no`, `Protocol 2`, `PermitEmptyPasswords no`,
  `X11Forwarding no`, explicit `KexAlgorithms`, `Ciphers`, `MACs`,
  `ClientAliveInterval`, `MaxAuthTries`.
- **Kernel sysctls** (look in `ansible.posix.sysctl`, `sysctl.d/*.conf`,
  templated `*.conf.j2`): `net.ipv4.conf.all.rp_filter=1`,
  `net.ipv4.conf.all.accept_redirects=0`,
  `net.ipv4.conf.all.send_redirects=0`,
  `net.ipv4.tcp_syncookies=1`, `kernel.randomize_va_space=2`,
  `kernel.kptr_restrict>=1`, `fs.suid_dumpable=0`.
- **Filesystem mount options** (`ansible.posix.mount`, `/etc/fstab.j2`):
  `nodev,nosuid,noexec` on `/tmp`, `/var/tmp`, `/dev/shm`; `nodev` on
  `/home`.
- **Auditd**: `auditd` package installed and started;
  `/etc/audit/rules.d/*.rules` templated; `-w /etc/passwd -p wa` family of
  watches present.
- **Host firewall**: `ufw`, `firewalld`, `nftables`, or `iptables` default
  policy `DROP` or `reject`; explicit allow-list rules.
- **Password policy**: `/etc/login.defs` (`PASS_MAX_DAYS`, `PASS_MIN_LEN`),
  `pam_pwquality.conf` (`minlen`, `dcredit`, `ucredit`, `ocredit`).
- **Banner / MOTD**: `/etc/issue`, `/etc/issue.net`, `/etc/motd` templated.
- **Time sync**: `chronyd` or `systemd-timesyncd` enabled.

For each control, record which role (if any) provides it. If none,
FINDING.

### 4. Detect Dangerous Patterns

Grep all role tasks for:

- `ansible.builtin.shell:` or `ansible.builtin.command:` with unquoted
  `{{ }}` variable interpolation in the command string.
- `become: yes` or `become: true` at play level with a large task count
  and no scoped `become_user:`.
- `file:` or `template:` creating files with `mode: 0777`, `mode: "0777"`,
  or any world-writable bits.
- `get_url:` without `checksum:`.
- `apt:` / `yum:` / `dnf:` with `validate_certs: no`.
- `ansible.builtin.user:` creating accounts without `password_lock: true`
  when no password is set.

Each hit is a FINDING with the file path and line number.

### 5. Report per Host Group

Do not produce a flat list. For every host group in scope, emit a
subsection naming the roles that target it and the controls it is missing
or violating.

## Output Format

```
## Linux Hardening Review — <inventory or path>

### Coverage Matrix

| Host group   | Roles applied       | SSH | Sysctl | Mounts | Auditd | Firewall | Pw policy | Banner | Time |
|--------------|---------------------|-----|--------|--------|--------|----------|-----------|--------|------|
| web_servers  | common, nginx       | OK  | OK     | GAP    | GAP    | OK       | OK        | GAP    | OK   |
| db_servers   | common, postgres    | OK  | OK     | OK     | OK     | OK       | GAP       | GAP    | OK   |

### Findings by Host Group

#### web_servers
- [FINDING] roles/common/tasks/mounts.yml — no nodev/nosuid/noexec on /tmp
- [FINDING] roles/common/tasks/audit.yml — auditd not declared
- [FINDING] roles/nginx/templates/nginx.service.j2:14 — unquoted {{ listen_port }} in ExecStart

#### db_servers
- [FINDING] roles/common/tasks/login.yml — PASS_MAX_DAYS not enforced
- [FINDING] roles/common/tasks/banner.yml — /etc/issue not templated

### Dangerous Patterns
- [FINDING] roles/common/tasks/bootstrap.yml:22 — world-writable mode 0777 on /opt/app
- [FINDING] roles/nginx/tasks/deploy.yml:8 — get_url without checksum

**Verdict:** <PASS | CONCERN | FAIL>
```

## Verdict

- **PASS**: every host group has coverage for every control and zero
  dangerous-pattern findings.
- **CONCERN**: up to three controls missing in total across all groups and
  no HIGH dangerous patterns (no world-writable file creation, no unquoted
  shell variable expansion).
- **FAIL**: any host group missing four or more controls, or any HIGH
  dangerous pattern present.
- **INCONCLUSIVE**: inventory unresolvable, no roles found, or required
  tooling (`ansible-inventory`) missing — surface as SKIPPED.

## Rules

1. **Read-only, repo-local.** Never SSH. Never run `ansible` ad-hoc
   commands. Never run `ansible-playbook` without `--check`. Allowed
   commands: `ansible-inventory --list`, `ansible-inventory --list --yaml`,
   `ansible-lint`, `ansible-playbook --check --diff`. Nothing else.
2. **No mutation.** Do not suggest commands that would change state on any
   host. Never call `ssh`, `rsync`, or `scp`.
3. **Static analysis only.** Coverage is analysis of declared state, not
   runtime verification. Call this out in every report.
4. **Graceful SKIPPED.** If Ansible inventory cannot be resolved or
   `ansible-inventory` is unavailable, mark the whole run SKIPPED with the
   reason and stop.
5. **Never fabricate.** Do not invent host names, CIS rule numbers, or
   group names. If scope cannot be determined, mark INCONCLUSIVE.
6. **Report, do not fix.** Report findings; never auto-edit roles.

$ARGUMENTS
