---
name: review-systemd-units
description: "Audit systemd unit files (in Ansible templates / roles / repo) for Restart, resource limits, and sandboxing directives."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[path]"
---

# systemd Unit Review

Audit systemd unit files that are declared or templated inside the
repository (roles, playbooks, templates, or raw unit files) for
reliability, resource-limit, and sandboxing directives. This skill is
strictly **read-only, repo-local** — it never SSHes to live hosts, never
queries `systemctl` on remote systems, and never applies changes.

## Invocation

The user runs `/review-systemd-units` with an optional path argument
scoping the audit to a specific role, directory, or single unit file.
Without an argument, scan every unit discoverable under the repository
root.

## Execution Steps

For each unit reviewed, record **PASS**, **FINDING**, or **SKIPPED**
(unreadable / malformed). For the overall run, report **N/A** when no
units are found in scope.

### 1. Find Units

Glob for unit files and their Jinja templates under the argument path (or
repo root). Patterns to enumerate:

- `**/*.service`, `**/*.service.j2`
- `**/*.timer`, `**/*.timer.j2`
- `**/*.socket`, `**/*.socket.j2`
- `**/*.target`, `**/*.mount`, `**/*.path`
- `roles/*/templates/**/*.j2` where the filename stem matches a unit type
- `roles/*/files/**/*.service`

If no units are found, mark the run **SKIPPED** with the reason and stop.

### 2. Check Reliability

For each `[Service]` section, parse and evaluate:

- `Restart=` — should be one of `on-failure`, `always`, or `on-abnormal`
  for long-running daemons. `Restart=no` on a daemon-style unit
  (`Type=simple` / `Type=notify` / `Type=forking` with no `RemainAfterExit`)
  is a FINDING.
- `RestartSec=` — present and >= 1s when `Restart=` is set. A missing
  `RestartSec=` combined with `Restart=always` is a FINDING (tight crash
  loop risk).
- `StartLimitBurst=` / `StartLimitIntervalSec=` — explicitly set for
  long-running daemons; unset pair is a low-severity FINDING.
- `TimeoutStartSec=` / `TimeoutStopSec=` — sane (not `infinity` unless
  justified in a preceding comment).

### 3. Check Resource Limits

For each service unit that is stateful, user-facing, or runs untrusted
workloads (detected heuristically: presence of `ExecStart=` referencing a
database, web server, or application binary), check that at least one of
the following is declared:

- `MemoryMax=` or `MemoryHigh=`
- `CPUQuota=`
- `TasksMax=`
- `IOWeight=` or `IOReadBandwidthMax=` / `IOWriteBandwidthMax=`
- `LimitNOFILE=`

Also check `OOMScoreAdjust=` is in the range `-1000..1000` if set, and
not aggressively negative (<= -900) without comment justification.

Units running in `system.slice` with no limits at all are a FINDING.

### 4. Check Sandboxing

For each service unit, check for presence of at least a baseline of the
following directives. Services that run as root (no `User=` set, or
`User=root`) with none of these declared are a **HIGH** FINDING.

- `ProtectSystem=` (prefer `strict` or `full`)
- `ProtectHome=` (prefer `yes` or `read-only`)
- `PrivateTmp=yes`
- `PrivateDevices=yes`
- `NoNewPrivileges=yes`
- `CapabilityBoundingSet=` (drop-list, not empty)
- `AmbientCapabilities=` (empty unless explicitly required)
- `SystemCallFilter=` (allow-list, e.g. `@system-service`)
- `RestrictAddressFamilies=`
- `RestrictNamespaces=yes`
- `LockPersonality=yes`
- `MemoryDenyWriteExecute=yes`
- `RestrictRealtime=yes`
- `ProtectKernelModules=yes`
- `ProtectKernelTunables=yes`
- `ProtectControlGroups=yes`

Missing 3+ of the baseline (`ProtectSystem`, `PrivateTmp`,
`NoNewPrivileges`, `ProtectHome`, `CapabilityBoundingSet`) is a FINDING.

### 5. Check Template Correctness

For every `.j2` template:

- Parse Jinja delimiters — `{{ }}`, `{% %}`, `{# #}` must balance. Use a
  `python3 -c 'from jinja2 import Environment; Environment().parse(open("...").read())'`
  probe or manual bracket scan.
- `ExecStart=` / `ExecStartPre=` / `ExecStopPost=` must not contain
  unquoted `{{ var }}` interpolations where the variable could contain
  whitespace. Quoting rule: `ExecStart=/usr/bin/app "{{ arg }}"`.
- `Environment=` / `EnvironmentFile=` referencing a path that the template
  does not also materialize is a low-severity FINDING.

## Output Format

```
## systemd Unit Review — <path or repo root>

| Unit                              | Reliability | Limits | Sandbox | Template | Verdict |
|-----------------------------------|-------------|--------|---------|----------|---------|
| roles/nginx/templates/nginx.service.j2 | OK      | GAP    | GAP     | OK       | FINDING |
| roles/api/templates/api.service.j2     | GAP     | OK     | OK      | OK       | FINDING |
| roles/timer/files/cleanup.timer        | OK      | N/A    | N/A     | OK       | PASS    |

### Findings

- [HIGH] roles/api/templates/api.service.j2 — runs as root, no ProtectSystem / PrivateTmp / NoNewPrivileges
- [FINDING] roles/nginx/templates/nginx.service.j2 — no MemoryMax / CPUQuota
- [FINDING] roles/api/templates/api.service.j2 — Restart=always with no RestartSec (crash loop risk)
- [FINDING] roles/web/templates/web.service.j2:12 — unquoted {{ listen_addr }} in ExecStart

**Totals:** units scanned: N, PASS: N, FINDING: N, HIGH: N
**Verdict:** <PASS | CONCERN | FAIL>
```

## Verdict

- **PASS**: every unit is PASS across all four columns.
- **CONCERN**: one or more FINDINGs, but no HIGH severity.
- **FAIL**: one or more HIGH findings (root daemon with no sandboxing,
  tight crash-loop configuration, unquoted variable in an `ExecStart=`
  command line).
- **N/A**: no units found in scope.

## Rules

1. **Read-only, repo-local.** Never SSH. Never call `systemctl`, `ssh`,
   `rsync`, or `scp` against a live host. Only static analysis of files
   on disk in the repo.
2. **No mutation.** Do not propose `ansible-playbook` without `--check`.
   Do not propose `systemctl daemon-reload`, `systemctl restart`, or
   `systemctl enable` against any host.
3. **No fabrication.** Never invent unit names, host names, or directive
   values. If a template's variables are unresolved, state that and mark
   the unit INCONCLUSIVE rather than guessing.
4. **Graceful SKIPPED.** If no units are found, report SKIPPED. If a
   template cannot be parsed, record it as SKIPPED for that unit only and
   continue.
5. **Report, do not fix.** Surface findings; never edit unit files or
   templates.

$ARGUMENTS
