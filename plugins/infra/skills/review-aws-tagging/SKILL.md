---
name: review-aws-tagging
description: "Audit AWS resource tag compliance against an organization taxonomy (cost center, owner, environment, data classification, etc.)."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
argument-hint: "[taxonomy-file or inline:key1,key2]"
---

# AWS Tag Compliance Review

Verify AWS resources are tagged in conformance with an organization taxonomy. Reports per-resource-type coverage, per-resource offender lists, and an overall compliance verdict. This skill is strictly **read-only** — it never mutates tags.

## Invocation

The user runs `/review-aws-tagging [taxonomy-file or inline:key1,key2,...]`. The argument may be:

- A path to a YAML taxonomy file.
- An `inline:` specifier listing required tag keys (for example `inline:Owner,CostCenter,Environment`).
- Omitted — the skill looks for `.claude/tagging-taxonomy.yml` or prompts for the taxonomy.

## Execution Steps

Run steps in order. Each step reports **PASS**, **FINDING**, **SKIPPED** (prerequisite missing), or **INCONCLUSIVE**. Never fabricate tag values, resource ARNs, or account ids.

### 1. Load Taxonomy

1. If the argument is a file path, read the YAML. Expected schema per tag:
   ```yaml
   tags:
     - key: Owner
       required: true
       severity: HIGH
       allowed_values: null         # freeform
       allowed_regex: "^[a-z0-9_-]+$"
     - key: Environment
       required: true
       severity: HIGH
       allowed_values: [prod, staging, dev, sandbox]
     - key: CostCenter
       required: true
       severity: MEDIUM
       allowed_regex: "^CC-[0-9]{4}$"
     - key: DataClassification
       required: false
       severity: LOW
       allowed_values: [public, internal, confidential, restricted]
   ```
2. If the argument is `inline:key1,key2,...`, synthesize a minimal taxonomy with every key `required: true, severity: MEDIUM`.
3. If neither is supplied, use AskUserQuestion to request the required tag keys and their allowed values.
4. If the taxonomy cannot be loaded, mark this step **SKIPPED** and stop.

### 2. Scan IaC

1. Glob for Terraform (`*.tf`), CloudFormation (`*.yaml`, `*.yml`, `*.json` templates), CDK output, and Pulumi code under the repo.
2. For each `aws_*` Terraform resource that supports tags, collect:
   - Its `tags = { ... }` block.
   - Any `default_tags` from the provider block in the same module.
   - Tags inherited via `locals` spread.
3. For each CloudFormation `AWS::*::*` resource, read its `Properties.Tags` list.
4. Resolve each resource's effective tag set — provider default_tags merged with resource-local tags, with resource-local winning on conflict.
5. Normalize tag keys to a case-sensitive form (AWS is case-sensitive). Do not silently lowercase.
6. For every effective tag set, compare against the taxonomy:
   - Required key missing → **MISSING** finding at the taxonomy-declared severity.
   - Key present but value fails `allowed_values` / `allowed_regex` → **INVALID** finding at the taxonomy-declared severity.
   - Unknown key not in taxonomy → report as HOUSEKEEPING (low priority), not a FINDING.

### 3. Scan Live (Optional)

1. Probe AWS credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

   ```bash
   AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
   [ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
   "$AUTH" aws
   ```

   If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark this step **SKIPPED** with the `detail` field as the reason and continue with IaC-only.
2. Ask via AskUserQuestion whether to include live scanning. Default to no.
3. If enabled, paginate `aws resourcegroupstaggingapi get-resources --tags-per-page 100` across the target regions. Capture `ResourceARN` and `Tags`.
4. For each ARN, diff against the taxonomy the same way as step 2.
5. Record resources that appear live but not in IaC as HOUSEKEEPING drift (likely click-ops) — surface them separately rather than mixing with tagging findings.

### 4. Compute Coverage

1. Bucket findings by AWS resource type (for example `aws_s3_bucket`, `aws_instance`, `aws_rds_cluster`).
2. For each bucket, compute `compliance % = (resources with all required tags present and valid) / (total resources)`.
3. Report any type below 100% as a row in the coverage matrix.

### 5. Report

1. Build the coverage matrix.
2. Build the offender list, grouped by severity (HIGH → MEDIUM → LOW).
3. For each offender, list the exact missing keys and invalid values — never propose a tag value that was not supplied by the user or present in the taxonomy.

## Output Format

```
## AWS Tagging Review — <taxonomy source>

**Scope:** <IaC | IaC + Live>     **Required tags:** Owner, Environment, CostCenter

### Coverage Matrix

| Resource Type          | Total | Fully Compliant | % |
| ---------------------- | ----- | --------------- | - |
| aws_s3_bucket          |    12 |              10 | 83% |
| aws_instance           |    34 |              20 | 59% |
| aws_rds_cluster        |     3 |               3 | 100% |
...

### Offenders — HIGH severity

| Resource | Missing | Invalid | Source |
| -------- | ------- | ------- | ------ |
| aws_s3_bucket.logs | Owner, Environment | — | terraform/storage/s3.tf:42 |
| aws_instance.bastion | — | Environment="production" (expected one of prod/staging/dev/sandbox) | terraform/network/bastion.tf:18 |
...

### Offenders — MEDIUM severity
...

### Housekeeping (unknown tags, live-only resources)
...

### Totals
- Scanned: <N> resources (<X> IaC, <Y> live)
- MISSING: <N>   INVALID: <N>   Compliant: <N>

### Verdict: <COMPLIANT | PARTIAL | NON-COMPLIANT>
```

## Verdict

- **COMPLIANT** — every required tag present with a valid value on every resource in scope.
- **PARTIAL** — 90% or more resources compliant and no HIGH-severity missing tags.
- **NON-COMPLIANT** — below 90% compliance, or any HIGH-severity missing tags, or any INVALID value with HIGH severity.

## Rules

1. **Read-only AWS calls only.** Use `aws resourcegroupstaggingapi get-resources`, `aws sts get-caller-identity`, and nothing else in this skill. Never emit `aws ec2 create-tags`, `aws s3api put-bucket-tagging`, `aws resourcegroupstaggingapi tag-resources`, or any other mutating command.
2. **Never fabricate tag values or ARNs.** Report only values that were read from IaC or live AWS responses. If the taxonomy demands a value you cannot verify, mark the field **INCONCLUSIVE**.
3. **Graceful skip.** If the taxonomy cannot be loaded, stop and report. If live scanning is enabled but `aws` or credentials are missing, mark live **SKIPPED** and continue with IaC-only.
4. **Case-sensitive keys.** Do not collapse `owner` and `Owner` — report them as distinct.
5. **Never propose tag values.** Suggest "add Owner tag" but do not invent a value like `Owner=platform-team` unless the user supplied that value in the taxonomy or the repo.
6. **No persona.** Procedural and imperative only.

$ARGUMENTS
