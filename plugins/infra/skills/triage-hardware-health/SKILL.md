---
name: triage-hardware-health
description: "Triage baremetal hardware health from Ansible fact caches or pre-collected reports — SMART disk data, mdadm/ZFS pool status, IPMI/BMC alerts, firmware/microcode currency."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
argument-hint: "[facts-dir or inventory-group]"
---

# Hardware Health Triage

Triage baremetal hardware health by reading Ansible fact caches and
pre-collected reports staged under the repository — `smartctl` JSON,
`mdadm --detail`, `zpool status`, `ipmitool sel list`, `dmidecode`, and
the `ansible_facts` blob under `.ansible/facts/`. This skill is strictly
**read-only, repo-local** — it never SSHes to live hosts and never runs
hardware commands against real hardware.

## Invocation

The user runs `/triage-hardware-health` with an optional argument pointing
at a directory of collected facts (e.g. `.ansible/facts/`,
`reports/hardware/2026-04-15/`) or an Ansible inventory group. Without an
argument, prompt the user for the path.

## Execution Steps

For each host / subsystem, report **OK**, **WARN**, **CRITICAL**, or
**SKIPPED** (data missing / stale / unparseable).

### 1. Locate Fact Cache

Resolve input:

- If argument is a path and it exists, use it directly.
- Else probe standard locations: `.ansible/facts/`, `facts/`,
  `ansible/facts/`, `reports/hardware/`, `inventory/host_vars/*/facts.*`.
- Else, if argument is an inventory group, enumerate its hosts via
  `ansible-inventory --list --yaml` and look for cached facts keyed by
  hostname under the standard locations.
- If nothing is found, use **AskUserQuestion** to prompt for the path to
  a collected report directory. Do not proceed without a path. Do not
  attempt to collect facts from live hosts.

Record, for every file consumed, its last-modified timestamp. Data older
than 7 days triggers a **STALE** flag on that host's section and a
warning at the top of the report.

### 2. SMART Triage

For each `smartctl --json --all` file found (or parseable text dumps),
evaluate per-attribute thresholds. Report a FINDING when any of the
following hold:

- `Reallocated_Sector_Ct` (attr 5) raw value > 0
- `Current_Pending_Sector` (attr 197) raw value > 0
- `Offline_Uncorrectable` (attr 198) raw value > 0
- `Reported_Uncorrect` (attr 187) raw value > 0
- `UDMA_CRC_Error_Count` (attr 199) raw value > 0 (cable / connector)
- `Temperature_Celsius` (attr 194) current value > 55
- `Power_On_Hours` (attr 9) approaching vendor MTBF when a
  `device_model` match is known (do not fabricate MTBF — if unknown,
  just report power-on-hours and mark confidence Low)
- SSD wear: `Percent_Lifetime_Used` / `Wear_Leveling_Count` /
  `Media_Wearout_Indicator` >= 80 % used

Also check `smart_status.passed == false` (overall health SMART verdict)
— that is always **CRITICAL**.

Record the per-disk verdict and the specific attributes that drove it.
Never invent raw values or thresholds for attributes not present in the
source file.

### 3. Array and Pool Status

- **mdadm** (`mdadm --detail /dev/md*` dumps): State line containing any
  of `degraded`, `FAILED`, `recovering`, `resyncing`, or an array map
  containing `_` in place of a member letter = FINDING. Note the
  resync / recovery progress percentage when present.
- **ZFS** (`zpool status` dumps): state `DEGRADED`, `FAULTED`,
  `UNAVAIL`, or `REMOVED` = FINDING. `ONLINE` with non-zero `READ`,
  `WRITE`, or `CKSUM` error columns = FINDING. `scan:` line indicating
  an active resilver = WARN.
- **Pool capacity**: any pool > 80 % full = WARN; > 90 % = CRITICAL.

### 4. IPMI / BMC Events

For each `ipmitool sel list` or `ipmitool sdr` dump:

- Any event in the last 30 days with severity `Critical`, `Non-Critical`,
  or keywords `Asserted`, `Predictive Failure`, `Uncorrectable`,
  `Correctable ECC` (when repeated) = FINDING.
- Sensor thresholds crossed (CPU temp, fan RPM, PSU voltage) in the
  current `sdr` output = FINDING.

### 5. Firmware and Microcode

For each host where `dmidecode` output is available:

- Record BIOS vendor, version, release date, CPU vendor and family.
- If an `intel-microcode` or `amd-ucode` package version is cached in the
  Ansible facts (`ansible_facts.packages`), surface the installed version.
- Do **not** fabricate CVE numbers or "latest" microcode versions. Note
  the installed version and the BIOS release date; flag **STALE** when
  the BIOS release date is more than 2 years old. For a specific CVE
  match, require the CVE id to appear in the input data — never invent.

### 6. Group by Host

Emit one card per host, then a consolidated "hosts at risk" list sorted
by worst-subsystem severity.

## Output Format

```
## Hardware Health Triage — <source>

Fact timestamp range: <oldest> .. <newest>
Stale hosts (>7d): N

### Per-Host Cards

#### host-a  (facts: 2026-04-14T10:22Z)
- Disks:     CRITICAL — sda: Reallocated_Sector_Ct=12, Current_Pending_Sector=4
- Arrays:    WARN     — md0 resyncing (63%)
- Pools:     OK
- IPMI:      OK       — no events in last 30d
- Firmware:  WARN     — BIOS release 2022-11 (>2y), microcode intel-microcode=3.20230808.1

#### host-b  (facts: 2026-04-09T06:00Z)  [STALE]
- Disks:     WARN     — nvme0: Percent_Lifetime_Used=84
- Arrays:    N/A
- Pools:     CRITICAL — tank 92% full
- IPMI:      SKIPPED  — no sel dump in report
- Firmware:  OK

### Hosts at Risk

| Host   | Worst subsystem | Severity | Notes                          |
|--------|-----------------|----------|--------------------------------|
| host-a | Disks           | CRITICAL | sda reallocations + pending    |
| host-b | Pools           | CRITICAL | tank 92% full; facts stale     |

**Totals:** hosts: N, CRITICAL: N, WARN: N, OK: N, STALE: N
**Verdict:** <PASS | CONCERN | FAIL>
```

## Verdict

- **PASS**: every host is OK across every subsystem and no STALE flags.
- **CONCERN**: one or more WARNs, zero CRITICALs.
- **FAIL**: one or more CRITICALs.
- **INCONCLUSIVE**: no usable input located after prompting — surface as
  SKIPPED with the reason.

## Rules

1. **Read-only, repo-local.** Never SSH. Never run `smartctl`, `mdadm`,
   `zpool`, `ipmitool`, or `dmidecode` against live hardware. Only parse
   files already on disk or at a user-provided path. Allowed commands:
   `ansible-inventory --list`, `ansible-lint`,
   `ansible-playbook --check --diff`. Nothing else.
2. **No mutation.** Do not propose `ansible-playbook` without `--check`,
   `ssh`, `rsync`, or `scp`. Findings may recommend vendor RMA procedures
   in prose only.
3. **Never fabricate.** Do not invent host names, serial numbers, SMART
   attribute values, microcode versions, MTBF numbers, or CVE ids. When
   a value is absent from the source, omit it or mark INCONCLUSIVE.
4. **Always timestamp.** Every per-host card must include the fact file
   timestamp. Data older than 7 days is flagged STALE in the summary.
5. **Graceful SKIPPED.** Missing inventory, missing fact cache, or
   unparseable dumps degrade to SKIPPED for the affected section only.
6. **Prompt, do not collect.** When facts are absent, use AskUserQuestion for the path. Never attempt live collection.

$ARGUMENTS
