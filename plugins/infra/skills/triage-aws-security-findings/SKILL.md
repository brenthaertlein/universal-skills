---
name: triage-aws-security-findings
description: "Consolidate AWS Security Hub, GuardDuty, Inspector, and Trusted Advisor findings into one deduplicated, ranked action list."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[account-id or path to findings JSON]"
---

# AWS Security Findings Triage

Pull and consolidate findings from AWS Security Hub, GuardDuty, Inspector, and Trusted Advisor. Deduplicate across products, rank by severity and exposure, and group by resource owner. This skill is strictly **read-only** — it never updates finding workflow status, never suppresses findings, and never mutates AWS resources.

## Invocation

The user runs `/triage-aws-security-findings [account-id or path]`. The argument may be:

- An AWS account id — the skill attempts live reads via the AWS CLI.
- A directory or file path — the skill parses exported finding JSON.
- Omitted — the skill looks for finding exports under `./security-findings/` and otherwise prompts.

## Execution Steps

Run steps in order. Each step reports **PASS**, **FINDING**, **SKIPPED** (prerequisite missing), or **INCONCLUSIVE**. Never fabricate finding ids, resource ARNs, CVE numbers, or remediation steps.

### 1. Collect Findings

1. If the argument resolves to a path, recursively read JSON files under it. Detect format per file by top-level keys:
   - Security Hub export: `Findings[].ProductArn`, `Findings[].Types`.
   - GuardDuty export: `Findings[].Service.Action`, `Findings[].Resource.ResourceType`.
   - Inspector v2 export: `findings[].findingArn`, `findings[].packageVulnerabilityDetails`.
   - Trusted Advisor export: `checks[].id`, `flaggedResources[]`.
2. If the argument looks like an account id or is absent and live mode is possible, probe AWS credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

   ```bash
   AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
   [ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
   "$AUTH" aws
   ```

   If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark live collection **SKIPPED** with the `detail` field as the reason and proceed with any exported JSON found.
3. In live mode, call read-only APIs only:
   - `aws securityhub get-findings --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' --max-results 100` (paginate via `--next-token`).
   - `aws guardduty list-detectors`, then for each detector id: `aws guardduty list-findings --detector-id <id>` and `aws guardduty get-findings --detector-id <id> --finding-ids <list>`.
   - `aws inspector2 list-findings --filter-criteria '{"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}'`.
   - `aws support describe-trusted-advisor-checks --language en` and `aws support describe-trusted-advisor-check-result --check-id <id>` (requires Business or Enterprise Support; mark **SKIPPED** on `SubscriptionRequiredException`).
4. Record the source product for every finding ingested.

### 2. Normalize

1. Collapse every finding into a single schema:
   ```
   {
     source:           "security-hub" | "guardduty" | "inspector" | "trusted-advisor",
     id:               <product finding id>,
     resource:         <ARN or resource identifier>,
     resource_type:    <AWS resource type>,
     severity:         "CRITICAL" | "HIGH" | "MEDIUM" | "LOW" | "INFORMATIONAL",
     first_seen:       <ISO 8601>,
     last_seen:        <ISO 8601>,
     title:            <short title>,
     standard_control: <NIST, CIS, PCI, or AWS Foundational control id if present>,
     exposure:         <"public" | "internet-facing" | "internal" | "unknown">
   }
   ```
2. Map product-specific severity strings to the canonical five-level scale.
3. Derive `exposure` from the resource fields where available — for example, Security Hub `Resources[].Details.AwsEc2SecurityGroup` with `0.0.0.0/0` ingress → `public`. Mark `unknown` when the input does not state exposure; do not guess.

### 3. Deduplicate

1. Key each finding by `(resource, standard_control or title-signature)`.
2. Collapse duplicates across products into one row with:
   - A `sources: []` list (for example `["security-hub", "trusted-advisor"]`).
   - The earliest `first_seen` and the latest `last_seen`.
   - The highest severity observed.
3. Record a `multiplicity` count equal to the number of product rows collapsed.

### 4. Group by Resource Owner

1. For each deduplicated finding, look up the resource's `Owner`, `Team`, or `CostCenter` tag if it is present in the source record.
2. If the finding record does not carry tags but the repo contains matching IaC, read the tag set from the IaC declaration.
3. If no owner can be determined, place the finding in an **Unowned** bucket.

### 5. Rank

Sort within each owner bucket by a composite score:

1. Severity weight: CRITICAL=100, HIGH=50, MEDIUM=20, LOW=5, INFORMATIONAL=1.
2. Multiply by exposure multiplier: `public`=3, `internet-facing`=2, `internal`=1, `unknown`=1.
3. Multiply by environment multiplier if the resource carries an `Environment` tag: `prod`=2, otherwise 1.
4. Secondary sort by `last_seen` descending so recent findings surface first at equal score.

Never invent remediation text. For each finding, cite only:

- The `title` and `standard_control` from the source record.
- A pointer to the canonical AWS docs URL that the source record supplies (do not construct URLs).

## Output Format

```
## AWS Security Findings Triage — <account-or-path>

**Sources collected:** Security Hub, GuardDuty, Inspector, Trusted Advisor
**Total findings:** <N>   **After dedup:** <N>   **Unowned:** <N>

### Totals by Severity
- CRITICAL: <N>   HIGH: <N>   MEDIUM: <N>   LOW: <N>   INFORMATIONAL: <N>

### Findings — Owner: platform-team

| Severity | Resource | Finding | Source(s) | First Seen | Remediation |
| -------- | -------- | ------- | --------- | ---------- | ----------- |
| CRITICAL | arn:aws:s3:::<bucket> | S3 bucket allows public read | security-hub, trusted-advisor | 2026-03-12 | Per AWS Foundational Control S3.1 — enable block-public-access |
| HIGH     | arn:aws:ec2:...:instance/i-... | GuardDuty: UnauthorizedAccess:EC2/SSHBruteForce | guardduty | 2026-04-10 | Per GuardDuty finding guidance; review source IPs and SG |
...

### Findings — Owner: data-team
...

### Findings — Unowned
...

### Verdict: <CLEAN | NEEDS-TRIAGE | CRITICAL>
```

## Verdict

- **CLEAN** — zero active CRITICAL or HIGH findings after deduplication.
- **NEEDS-TRIAGE** — one or more HIGH findings, or more than ten MEDIUM findings, but no active CRITICAL.
- **CRITICAL** — one or more CRITICAL findings, or any HIGH finding on a publicly exposed resource.

## Rules

1. **Read-only AWS calls only.** Use `get-findings`, `list-findings`, `describe-*`, `list-detectors`, `get-caller-identity`. Never emit `aws securityhub update-findings`, `aws securityhub batch-update-findings`, `aws guardduty update-findings-feedback`, `aws guardduty archive-findings`, `aws inspector2 update-*`, or any other mutating command.
2. **Never fabricate finding ids, resource ARNs, severities, CVE numbers, or control numbers.** Emit only what appears in the source record. If a field is missing, mark it **INCONCLUSIVE** or leave it blank.
3. **Never invent remediation text.** Cite the AWS Foundational Security Best Practices control id, the GuardDuty finding type, the Inspector package id, or the Trusted Advisor check id from the source record — no paraphrased fixes.
4. **Graceful skip.** If `aws` is unavailable or credentials fail, fall back to parsing JSON exports. If no input is available in either mode, report the skill as **SKIPPED** with the reason.
5. **Do not suppress or mutate finding state.** Even if a finding is known-accepted, record that observation in the report — never call an API that changes workflow status.
6. **No persona.** Procedural and imperative only.

$ARGUMENTS
