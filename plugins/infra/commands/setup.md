---
name: setup
description: Configure recommended permissions for the infra plugin
---

Configure recommended permissions for the infra plugin by merging them into `.claude/settings.json`.

## Recommended Permissions

The following permissions should be added to `.claude/settings.json` under `permissions.allow`:

```json
[
  "Bash(terraform fmt -check*)",
  "Bash(terraform validate*)",
  "Bash(terraform plan*)",
  "Bash(terraform show -json*)",
  "Bash(terraform plan -detailed-exitcode*)",
  "Bash(pulumi preview --diff*)",
  "Bash(ansible-lint*)",
  "Bash(ansible-inventory*)",
  "Bash(ansible-inventory --list*)",
  "Bash(ansible-playbook --check --diff*)",
  "Bash(kubectl get*)",
  "Bash(kubectl describe*)",
  "Bash(kubectl kustomize*)",
  "Bash(kubectl diff*)",
  "Bash(helm lint*)",
  "Bash(helm list*)",
  "Bash(helm show*)",
  "Bash(docker compose config*)",
  "Bash(python3 -c \"import yaml*)",
  "Bash(aws ec2 describe-*)",
  "Bash(aws iam get-*)",
  "Bash(aws iam list-*)",
  "Bash(aws iam generate-service-last-accessed-details*)",
  "Bash(aws iam get-service-last-accessed-details*)",
  "Bash(aws securityhub get-findings*)",
  "Bash(aws guardduty list-findings*)",
  "Bash(aws guardduty get-findings*)",
  "Bash(aws guardduty list-detectors*)",
  "Bash(aws inspector2 list-findings*)",
  "Bash(aws resourcegroupstaggingapi get-resources*)",
  "Bash(aws s3api list-buckets*)",
  "Bash(aws s3api get-bucket-tagging*)",
  "Bash(aws cloudformation detect-stack-drift*)",
  "Bash(aws cloudformation describe-stack-resource-drifts*)",
  "Bash(aws backup list-backup-plans*)",
  "Bash(aws backup list-backup-vaults*)",
  "Bash(aws elbv2 describe-load-balancers*)",
  "Bash(aws rds describe-db-instances*)",
  "Bash(aws rds describe-db-snapshots*)",
  "Bash(aws support describe-trusted-advisor-checks*)",
  "Bash(aws accessanalyzer list-findings*)",
  "Bash(gcloud projects get-iam-policy*)",
  "Bash(gcloud resource-manager folders get-iam-policy*)",
  "Bash(gcloud resource-manager organizations get-iam-policy*)",
  "Bash(gcloud compute instances list*)",
  "Bash(gcloud compute disks list*)",
  "Bash(gcloud compute addresses list*)",
  "Bash(gcloud recommender recommendations list*)",
  "Bash(gcloud container clusters describe*)",
  "Bash(gcloud container clusters list*)",
  "Bash(gcloud iam service-accounts list*)",
  "Bash(gcloud iam service-accounts keys list*)",
  "Bash(kubectl get clusterroles*)",
  "Bash(kubectl get roles*)",
  "Bash(kubectl get clusterrolebindings*)",
  "Bash(kubectl get rolebindings*)",
  "Bash(kubectl get serviceaccounts*)",
  "Bash(smartctl -a*)",
  "Bash(smartctl --all*)",
  "Bash(smartctl --json*)",
  "Bash(mdadm --detail*)",
  "Bash(zpool status*)",
  "Bash(zpool list*)",
  "Bash(ipmitool sel list*)",
  "Bash(ipmitool sensor list*)",
  "Bash(dmidecode*)"
]
```

> **Note:** Only read-only and validation operations are auto-allowed. Mutating operations (terraform apply, kubectl apply, helm upgrade, ansible-playbook without `--check`, `aws * create/put/update/delete`, `gcloud * create/update/delete`, `gcloud iam * add-iam-policy-binding`) will always prompt for approval.

## Instructions

When this command is invoked, follow these steps exactly:

1. **Read** `.claude/settings.json` if it exists. If it does not exist, start with an empty object `{}`.
2. **Parse** the JSON. Extract the existing `permissions.allow` array. If `permissions` or `permissions.allow` does not exist, treat it as an empty array.
3. **Merge** the recommended permissions listed above into the existing `permissions.allow` array. Do NOT add duplicates -- skip any permission that already exists in the array.
4. **Write** the updated JSON back to `.claude/settings.json`, preserving all other existing keys and values in the file. Use 2-space indentation for readability.
5. **Report** the result to the user: "Added N permissions for infra plugin. Existing permissions preserved." where N is the number of new permissions that were actually added (not already present). If all permissions were already present, say "All infra plugin permissions already configured. No changes needed."
