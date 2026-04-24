---
name: review-aws-iam
description: "AWS IAM least-privilege audit for roles, policies, and user permissions declared in Terraform / CloudFormation or live in the account."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - WebFetch
argument-hint: "[role-or-policy-ARN or path]"
---

# AWS IAM Least-Privilege Review

Audit AWS IAM roles, policies, groups, and users for overly broad permissions, wildcard abuse, privilege-escalation paths, and weak trust policies. The audit covers both Infrastructure-as-Code declarations and live account state. This skill is strictly **read-only** — it never mutates IAM.

## Invocation

The user runs `/review-aws-iam [target]` where `[target]` is either:

- An IAM ARN (role, policy, user, or group) — the skill calls read-only IAM APIs.
- A filesystem path — the skill parses `aws_iam_*` Terraform resources or `AWS::IAM::*` CloudFormation resources under that path.
- Omitted — the skill scans the repo root for IaC IAM declarations.

## Execution Steps

Run steps in order. For each step, report **PASS**, **FINDING**, **SKIPPED** (prerequisite missing), or **INCONCLUSIVE** (context insufficient). Never fabricate ARNs, account IDs, or action names.

### 1. Collect Scope

1. Resolve the argument.
   - If the argument looks like an ARN (`arn:aws:iam::...`), mark the run as **live mode**.
   - If the argument is a directory or file path, mark the run as **IaC mode**.
   - If absent, scan the repo for `aws_iam_role`, `aws_iam_policy`, `aws_iam_policy_document`, `aws_iam_role_policy`, `aws_iam_user`, `aws_iam_group`, and CloudFormation `AWS::IAM::*` blocks.
2. In live mode, probe AWS credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

   ```bash
   AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
   [ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
   "$AUTH" aws
   ```

   Parse the JSON. If `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark this step **SKIPPED** with the `detail` field as the reason and stop live probing. Only proceed when `status` is `OK`.
3. In live mode, collect read-only context only:
   - `aws iam get-role --role-name <name>`
   - `aws iam get-policy --policy-arn <arn>` and `aws iam get-policy-version`
   - `aws iam list-attached-role-policies --role-name <name>`
   - `aws iam list-role-policies --role-name <name>` and `aws iam get-role-policy`
   - `aws iam list-entities-for-policy --policy-arn <arn>`
4. Record every resolved target. Do not invent ARNs that were not returned by these calls.

### 2. Flag Wildcards

1. For every policy document collected, enumerate each `Statement` with `Effect: Allow`.
2. Report a **FINDING** when any of the following is present without a scoping condition:
   - `Action: "*"` — always HIGH severity.
   - `Resource: "*"` paired with write or modify actions (`*:Create*`, `*:Put*`, `*:Delete*`, `*:Update*`, `iam:*`, `kms:*`, `s3:*`, `ec2:*`, `secretsmanager:*`).
   - Service wildcards (`s3:*`, `ec2:*`, `dynamodb:*`) when the role's usage evidence suggests a narrower set (for example the role only has CloudTrail records for `s3:GetObject` and `s3:ListBucket`).
3. Where the repo contains CloudTrail or Access Analyzer evidence, suggest the observed-action set verbatim. Never invent action names — if you cannot verify an action exists, cite the AWS Service Authorization Reference (via WebFetch to `https://docs.aws.amazon.com/service-authorization/latest/reference/`).

### 3. Detect Privilege-Escalation Paths

Check each policy for the standard AWS privesc primitives. Treat every match as a **FINDING** at HIGH severity unless the resource is narrowly scoped.

1. `iam:PassRole` with `Resource: "*"` or without an `iam:PassedToService` condition.
2. `iam:CreatePolicy`, `iam:CreatePolicyVersion`, `iam:SetDefaultPolicyVersion`, `iam:AttachRolePolicy`, `iam:AttachUserPolicy`, `iam:PutRolePolicy`, `iam:PutUserPolicy`.
3. `iam:CreateAccessKey`, `iam:UpdateLoginProfile`, `iam:CreateLoginProfile`.
4. `sts:AssumeRole` targets that include roles with `AdministratorAccess` or equivalent.
5. `lambda:UpdateFunctionCode`, `lambda:CreateFunction` plus `iam:PassRole` — code-execution-as-role path.
6. `ec2:RunInstances` combined with `iam:PassRole` — instance profile escalation.
7. `cloudformation:CreateStack`, `cloudformation:UpdateStack` with `iam:PassRole` — stack-role escalation.

For each finding, name the exact primitive matched and the policy ARN or file path and line number.

### 4. Trust-Policy Sanity

1. For every role trust policy, enumerate each `Principal` entry.
2. Report **FINDING** when:
   - `Principal: "*"` appears without an `aws:PrincipalOrgID`, `aws:SourceIp`, or `aws:SourceVpce` condition.
   - A service principal (for example `lambda.amazonaws.com`) lacks an `aws:SourceAccount` or `aws:SourceArn` condition — this is the confused-deputy pattern.
   - A cross-account principal is granted without an `ExternalId` condition on `sts:AssumeRole`.
   - The `sts:AssumeRoleWithWebIdentity` trust omits `sub` or `aud` claim conditions for OIDC providers.
3. Report **PASS** only when every principal is scoped by at least one condition key or is an in-account role.

### 5. Inventory Unused Permissions

1. If IAM Access Analyzer last-accessed data is available, call `aws iam generate-service-last-accessed-details` and `aws iam get-service-last-accessed-details` for each in-scope role.
2. List every service granted but not used in the last 90 days.
3. If Access Analyzer data is unavailable, mark this step **INCONCLUSIVE** and do not guess usage.

## Output Format

```
## AWS IAM Review — <target>

### Summary

| Check             | Status   | Findings |
| ----------------- | -------- | -------- |
| Scope Collection  | PASS     | 4 policies, 2 roles |
| Wildcard Actions  | FINDING  | 3 HIGH, 1 MEDIUM |
| Privesc Paths     | FINDING  | 1 HIGH |
| Trust Policies    | PASS     | 0 |
| Unused Services   | INCONCLUSIVE | Access Analyzer data not available |

### Findings

| Policy | Severity | Issue | Remediation |
| ------ | -------- | ----- | ----------- |
| arn:aws:iam::<acct>:policy/DeployerAccess | HIGH | iam:PassRole with Resource: "*" | Scope Resource to the specific service role ARNs; add iam:PassedToService condition |
| terraform/modules/ci/policies.tf:42 | MEDIUM | s3:* on Resource: "*" | Replace with observed actions (s3:GetObject, s3:PutObject) scoped to the build bucket |
...

### Verdict: <CLEAN | CONCERN | HIGH-RISK>
```

## Verdict

- **CLEAN** — no HIGH findings and no trust-policy findings.
- **CONCERN** — any MEDIUM findings, or INCONCLUSIVE steps that block a confident read.
- **HIGH-RISK** — one or more HIGH findings (wildcards on privileged services, privesc primitives, or open trust policies).

## Rules

1. **Read-only AWS calls only.** Never emit `aws iam put-*`, `aws iam create-*`, `aws iam update-*`, `aws iam attach-*`, `aws iam detach-*`, `aws iam delete-*`, or any other mutating command. Limit yourself to `get-*`, `list-*`, `describe-*`, and `generate-service-last-accessed-details` (which is a read request that produces a job id).
2. **Never fabricate ARNs, account IDs, or IAM action names.** Cite only what was returned by a read call, what appears in the parsed IaC, or what is in the AWS Service Authorization Reference.
3. **Graceful skip.** If `aws` is not installed, if `sts get-caller-identity` fails, or if no IaC IAM resources are found, mark the relevant step **SKIPPED** with the reason and continue.
4. **Quote minimized policies in full.** When proposing a tighter policy, write out the action list verbatim and label it as "observed actions" or "reference-documented actions" — never as "recommended."
5. **No persona.** Procedural and imperative only.

$ARGUMENTS
