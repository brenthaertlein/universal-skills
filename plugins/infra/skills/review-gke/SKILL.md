---
name: review-gke
description: "[pr-review-focus-area: GKE] GKE cluster hardening and cost review — Autopilot vs Standard, workload identity, node-pool sizing, cluster autoscaler, network policy."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[cluster-name or path to terraform]"
---

# GKE Cluster Review

Audit a Google Kubernetes Engine cluster for hardening and cost posture — mode (Autopilot vs Standard), workload identity, private control plane, node-pool shape, autoscaler bounds, network policy, and release channel currency. This skill is **read-only** — it only issues `gcloud container clusters describe|list` and Terraform file reads, never `create`, `update`, `upgrade`, or `delete`.

## Invocation

The user runs `/review-gke <cluster-name-or-path>`.

- If the argument resolves to a filesystem path, parse Terraform under it for `google_container_cluster` and `google_container_node_pool`.
- Otherwise treat the argument as a cluster name and require `gcloud container clusters list` to resolve its location.
- If no argument is given, run `gcloud container clusters list --format=json` and ask the user to pick one. Never guess.

## Execution Steps

Each step reports **PASS**, **CONCERN**, **FINDING**, **SKIPPED**, or **INCONCLUSIVE**.

### 1. Identify Cluster

1. Probe GCP credentials with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

   ```bash
   AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
   [ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
   "$AUTH" gcp
   ```

   If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, fall back to Terraform-only review and mark live steps SKIPPED with the `detail` field as the reason.
2. Resolve the cluster: `gcloud container clusters list --filter="name=<name>" --format=json`.
3. Capture full detail: `gcloud container clusters describe <name> --region=<region-or-zone> --format=json`. Save the JSON object for later steps.
4. Capture node pools: `gcloud container node-pools list --cluster=<name> --region=<region-or-zone> --format=json`.
5. When Terraform is the source, Read every `.tf` file matched by `grep -rln 'google_container_cluster\|google_container_node_pool' <path>`.

Do not fabricate cluster names, regions, or node-pool shapes.

### 2. Hardening Checklist

Evaluate each control. Emit a matrix cell colored GREEN (PASS), YELLOW (CONCERN), or RED (FINDING).

| Control                     | Evidence field                                    |
| --------------------------- | ------------------------------------------------- |
| Shielded nodes              | `nodeConfig.shieldedInstanceConfig.enableIntegrityMonitoring` + `.enableSecureBoot` |
| Workload Identity           | `workloadIdentityConfig.workloadPool`             |
| Private nodes               | `privateClusterConfig.enablePrivateNodes`         |
| Private endpoint            | `privateClusterConfig.enablePrivateEndpoint`      |
| Master authorized networks  | `masterAuthorizedNetworksConfig.enabled` + cidrBlocks non-empty |
| Release channel             | `releaseChannel.channel` in `{REGULAR, STABLE}`   |
| Binary Authorization        | `binaryAuthorization.evaluationMode` != `DISABLED`|
| Node auto-upgrade           | per node pool `management.autoUpgrade`            |
| Node auto-repair            | per node pool `management.autoRepair`             |
| Dataplane V2                | `networkConfig.datapathProvider == ADVANCED_DATAPATH` |
| Network policy              | `networkPolicy.enabled` OR Dataplane V2 in use    |
| Legacy ABAC off             | `legacyAbac.enabled == false`                     |
| Intra-node visibility       | `networkConfig.enableIntraNodeVisibility`         |
| Basic auth disabled         | `masterAuth.username == ""`                       |
| Client certificate disabled | `masterAuth.clientCertificateConfig.issueClientCertificate == false` |

Any RED cell becomes a FINDING. YELLOW cells (for example, release channel `UNSPECIFIED` or `RAPID`) become CONCERN.

### 3. Cost Checklist

Evaluate each lever against the collected data:

1. **Mode selection** — if the cluster is Standard and every node pool is general-purpose with fewer than 3 total nodes, emit CONCERN `consider-autopilot`.
2. **Node-pool rightsizing** — for each pool, compare `initialNodeCount * machineType CPU` against scheduled pod requests if known; otherwise emit INCONCLUSIVE with a note.
3. **Spot / preemptible coverage** — any pool named with `batch`, `ci`, or `dev` that is not `spot: true` → CONCERN.
4. **Autoscaler bounds** — for each pool with `autoscaling.enabled=true`, check `minNodeCount >= 1` (HA) and `maxNodeCount` is neither unset nor absurdly large (>100 without justification) → CONCERN.
5. **Idle pools** — pools with `initialNodeCount=0` and `autoscaling.enabled=false` → FINDING `dead-pool`.
6. **Disk shape** — node config `diskType == pd-standard` on control-plane-critical pools → CONCERN (prefer `pd-balanced` or `pd-ssd`).

### 4. Version and EOL

1. Extract `currentMasterVersion` and `currentNodeVersion` from cluster JSON.
2. Derive the minor version (for example `1.29.5-gke.1000` → `1.29`).
3. Compare to the channel's supported window as reported by `gcloud container get-server-config --region=<region> --format=json` (`validMasterVersions`, `channels[].defaultVersion`, `channels[].validVersions`).
4. If the cluster's minor is older than the channel's oldest valid minor, emit FINDING `eol-soon`. If equal to the oldest valid minor, emit CONCERN.

Do not fabricate EOL dates. If `get-server-config` is unavailable, mark this step INCONCLUSIVE.

### 5. Hand-Off

At the end of the report, print a short next-steps block:

- Recommend `/review-kubernetes-rbac` against the cluster's context for in-cluster permission review.
- Recommend `/review-observability` for dashboards and alert coverage.
- Recommend `/review-costs` if cost CONCERNs dominate.

Do not invoke these skills automatically.

## Output Format

```
## GKE Review — <cluster-name> (<location>)

### Hardening Matrix
| Control                   | Status | Evidence                        |
| ------------------------- | ------ | ------------------------------- |
| Shielded nodes            | GREEN  | integrity+secureBoot on         |
| Workload Identity         | RED    | workloadPool unset              |
| Private nodes             | GREEN  | enablePrivateNodes=true         |
| Master authorized nets    | YELLOW | enabled, 0.0.0.0/0 present      |
| Release channel           | GREEN  | REGULAR                         |
| Binary Authorization      | RED    | evaluationMode=DISABLED         |

### Cost Matrix
| Lever                 | Status | Note                              |
| --------------------- | ------ | --------------------------------- |
| Mode (Autopilot/Std)  | GREEN  | Standard, 12 nodes                |
| Spot coverage         | YELLOW | pool 'ci' is on-demand            |
| Autoscaler bounds     | GREEN  | min=1 max=20                      |
| Idle pools            | RED    | pool 'legacy' has 0 nodes, no AS  |

### Version & EOL
- Master: 1.27.11-gke.1000  → FINDING: older than channel minimum (1.28)
- Nodes:  1.27.11-gke.1000  → FINDING

### Next Steps
- /review-kubernetes-rbac  <context>
- /review-observability    <service-or-cluster>

**Verdict: NEEDS-HARDENING** (2 RED hardening, 1 RED cost, 2 version findings)
```

## Verdict

- **HARDENED** — zero RED cells anywhere, no EOL findings.
- **NEEDS-HARDENING** — one or more RED cells, or the cluster version is at or past channel EOL.
- **INCONCLUSIVE** — cluster could not be described and no Terraform is available to fall back to.

## Rules

1. **Read-only.** Only `gcloud container clusters describe|list`, `gcloud container node-pools list`, and `gcloud container get-server-config` are permitted. Never call `clusters create|update|upgrade|delete`, `node-pools create|update|delete`, or any `gcloud * create|update|delete` variant.
2. **No kubectl mutation.** If `kubectl` is used to fetch context metadata, only `kubectl config current-context` and `kubectl config view` are allowed. No `apply`, `delete`, `patch`, `edit`, `create`, or `exec`.
3. **Graceful skip.** Missing `gcloud`, missing credentials, or cluster-not-found must resolve to SKIPPED with a reason; if Terraform is available, continue in static mode.
4. **Never fabricate.** Do not invent cluster names, region/zone strings, machine types, node counts, version numbers, or EOL dates. When unknown, emit INCONCLUSIVE.
5. **Cross-skill handoff.** Mention `/review-kubernetes-rbac` and `/review-observability` in the output; never invoke them.

$ARGUMENTS
