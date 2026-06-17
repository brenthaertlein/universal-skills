---
name: triage-vulnerabilities
description: "Triage CVE and SBOM scanner output (Trivy, Grype, Snyk, Docker Scout, Dependabot) into a ranked, deduplicated action list."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - WebFetch
argument-hint: "[path to scanner report]"
---

# Vulnerability Triage

Normalize, deduplicate, and rank vulnerability scanner output from Trivy, Grype, Snyk, SARIF, Docker Scout, and GitHub Dependabot into a single ship-ordered action list. This skill is **read-only** — it never edits lockfiles, bumps package versions, or runs remediation commands.

## Invocation

The user runs `/triage-vulnerabilities <path to scanner report>`. The path may be a single JSON/SARIF file or a directory containing multiple scanner outputs. When omitted, scan the current directory for files matching `*-scan.json`, `trivy*.json`, `grype*.json`, `snyk*.json`, `*.sarif`, or `dependabot-alerts.json`.

## Execution Steps

### 1. Detect Scanner Format

Inspect each input file and identify its format by top-level keys:

| Format     | Detection signal                                                |
| ---------- | --------------------------------------------------------------- |
| Trivy      | Top-level `Results[]` with `Vulnerabilities[]` and `ArtifactName` |
| Grype      | Top-level `matches[]` with `vulnerability.id` and `artifact.name` |
| Snyk       | Top-level `vulnerabilities[]` with `id` prefixed `SNYK-` or `CVE-` |
| SARIF      | `$schema` containing `sarif-schema`, `runs[].results[]`          |
| Scout      | `vulnerabilities[]` with `source: "docker-scout"` or Scout CLI header |
| Dependabot | GitHub API shape: `security_advisory`, `dependency.package`      |

If a file does not match any known format, mark it SKIPPED with the reason and continue.

### 2. Normalize

Collapse every input row into the canonical record:

```
{
  "id":                 "<CVE-XXXX-NNNN or GHSA-xxxx or vendor ID>",
  "package":            "<name>",
  "version":            "<installed version>",
  "fixed_in":           "<version string or null>",
  "severity":           "<CRITICAL|HIGH|MEDIUM|LOW|UNKNOWN>",
  "cvss":               "<numeric score or null>",
  "reachable_from":     "<image ref, file path, or service>",
  "introduced_by_layer": "<layer digest or null>"
}
```

Preserve the original scanner name in a `source` field so the report can cite provenance. Never invent `fixed_in` — if the source record does not provide it, write `null`.

### 3. Deduplicate

Group records by `(id, package, version)`. Collapse the group to a single row with:

- `multiplicity` — count of distinct `reachable_from` values.
- `reachable_from` — list (capped at 5 entries in the output; include total count when truncated).
- `sources` — deduplicated list of scanner names that reported it.

Do not collapse across packages or versions; an upgrade that fixes one version may not fix another.

### 4. Enrich

For every deduplicated record with `severity` of CRITICAL or HIGH and `fixed_in` equal to `null`:

1. WebFetch the NVD record at `https://nvd.nist.gov/vuln/detail/<CVE-ID>` if the id is a CVE.
2. WebFetch the GHSA record at `https://github.com/advisories/<GHSA-ID>` if the id is a GHSA.
3. Extract any documented workaround, configuration mitigation, or linked upstream issue. Record under `workaround` on the row.
4. Also WebFetch the CISA Known Exploited Vulnerabilities catalog once per session (`https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json`) and tag matching rows with `kev: true`.

Network failures are non-fatal — leave the enrichment fields empty and continue.

### 5. Rank

Sort rows top-to-bottom by this priority chain:

1. `kev: true` (CISA KEV catalog match) first.
2. Then by `severity` (CRITICAL > HIGH > MEDIUM > LOW > UNKNOWN).
3. Then by `fixed_in` non-null (fixable sorts above unfixable at the same severity).
4. Then by deployment exposure (`multiplicity` of prod-tagged `reachable_from` descending).
5. Then by `cvss` descending.

Partition the sorted list into three buckets:

- **Fix now (ship today)** — KEV matches OR (CRITICAL/HIGH with `fixed_in` present and reachable from a prod artifact).
- **Fix this sprint** — remaining HIGH and MEDIUM with `fixed_in` present.
- **Accept risk / no fix available** — rows with `fixed_in: null` OR severity LOW/UNKNOWN.

## Senior Review

After ranking, dispatch to the `appsec-engineer` subagent with the bucketed rows. Ask it to sanity-check reachability — which advisories (by normalized `id`, whether CVE, GHSA, or vendor) sit in code paths actually exercised by a prod artifact versus theoretical — and to confirm the "Fix now" bucket reflects real exploitable risk. Integrate its read into the report below. It must **not** re-score severities (see Rule 5) or invent fix versions (Rule 4); it advises on prioritization and reachability only.

```
Agent({
  subagent_type: "appsec-engineer",
  description: "Sanity-check vuln triage",
  prompt: "Here are triaged vulnerabilities in three buckets (Fix now / Fix this sprint / Accept risk), each with id (CVE/GHSA/vendor), package, severity-as-given, fixed_in, and where it was found: <rows>. Without re-scoring severity, assess reachability — which are in paths actually exercised by a prod artifact versus theoretical — and confirm whether the 'Fix now' bucket reflects real exploitable risk. Flag any row whose bucket should change on reachability grounds, with a one-line attack-path rationale."
})
```

## Output Format

```
## Vulnerability Triage - <source>

**Inputs:** <N files, scanners: trivy, grype, ...>
**Normalized rows:** <N>   **After dedup:** <N>   **KEV matches:** <N>

### Fix now (ship today)
| CVE | Package | Fixed in | Severity | Found in |
|-----|---------|----------|----------|----------|
| CVE-YYYY-NNNN | libfoo | 1.2.4 | CRITICAL | api-svc:prod (x3) |

### Fix this sprint
| CVE | Package | Fixed in | Severity | Found in |
|-----|---------|----------|----------|----------|
| CVE-YYYY-MMMM | libbar | 3.0.1 | HIGH | worker:staging |

### Accept risk / no fix available
| CVE | Package | Severity | Workaround | Found in |
|-----|---------|----------|------------|----------|
| CVE-YYYY-PPPP | libbaz | HIGH | Disable module X | edge:prod |

**Verdict:** <CLEAN | ACTION-REQUIRED | CRITICAL-ACTION>
```

## Verdict

- **CLEAN** — zero rows in `Fix now`, zero KEV matches, all `Fix this sprint` rows under 10.
- **ACTION-REQUIRED** — non-empty `Fix this sprint` bucket or `Fix now` bucket with 1-3 rows and no KEV.
- **CRITICAL-ACTION** — any KEV match, OR four or more rows in `Fix now`, OR any CRITICAL row reachable from a prod artifact.

## Rules

1. **Read-only.** Never modify lockfiles, package manifests, Dockerfiles, or SBOM files. Never run `npm audit fix`, `pip install --upgrade`, `docker pull`, or any remediation command.
2. **Graceful skip.** If WebFetch fails, a scanner output is malformed, or a file format is unrecognized, mark that input SKIPPED and continue.
3. **No fabricated CVEs.** Never invent a CVE number, GHSA ID, or CVSS score. If a row lacks an identifier, keep it but flag the source record.
4. **No fabricated fix versions.** Only populate `fixed_in` when the source scanner reports it or an NVD/GHSA page explicitly lists a fixed release. If unknown, write "no fix available" in the report.
5. **Respect severity as-given.** Do not re-score vulnerabilities. Use the severity the scanner provided unless an advisory explicitly supersedes it.
6. **Cite sources.** Every enriched row must list the advisory URL that produced the enrichment so the user can verify.

$ARGUMENTS
