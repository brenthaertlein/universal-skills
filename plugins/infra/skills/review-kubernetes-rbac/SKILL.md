---
name: review-kubernetes-rbac
description: "[pr-review-focus-area: Kubernetes RBAC] Audit Kubernetes RBAC across a cluster — ClusterRoles, Roles, bindings, and ServiceAccount permissions. Works on EKS, GKE, AKS, and on-prem."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
argument-hint: "[context-or-manifest-path]"
---

# Kubernetes RBAC Audit

Audit ClusterRoles, Roles, ClusterRoleBindings, RoleBindings, and ServiceAccount membership for excess verbs, privilege-escalation paths, over-broad subjects, and unused rules. Works against a live cluster via `kubectl` or against manifests on disk. This skill is **read-only** — it only issues `kubectl get`, `describe`, and `diff`, and never `apply`, `delete`, `patch`, `edit`, `create`, or `exec`.

## Invocation

The user runs `/review-kubernetes-rbac <context-or-manifest-path>`.

- If the argument resolves to a filesystem path, parse YAML manifests under it (kustomize, helm templates, raw `.yaml`/`.yml`).
- Otherwise treat the argument as a kubeconfig context and confirm with `kubectl config get-contexts <arg>` before any live query.
- If no argument is given, use `kubectl config current-context` and confirm the resolved context with the user before proceeding.

## Execution Steps

Each step reports **PASS**, **FINDING**, **SKIPPED**, or **INCONCLUSIVE**.

### 1. Collect

Before any live call, probe the kubectl context with the shared helper. Prefer `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-auth-check.sh` and fall back to `plugins/infra/scripts/cloud-auth-check.sh` when running from the plugin dev repo.

```bash
AUTH="${CLAUDE_PLUGIN_ROOT:-plugins/infra}/scripts/cloud-auth-check.sh"
[ -x "$AUTH" ] || AUTH="plugins/infra/scripts/cloud-auth-check.sh"
"$AUTH" kubectl
```

If the JSON `status` is `MISSING_CLI`, `UNAUTHENTICATED`, or `EXPIRED`, mark live collection SKIPPED with the `detail` field as the reason and fall back to manifests. If neither source yields objects, emit INCONCLUSIVE and stop.

Gather the RBAC object set from one of two sources; never mix fabricated rules with collected ones.

**Live cluster:**

```
kubectl --context=<ctx> get clusterroles -o yaml
kubectl --context=<ctx> get clusterrolebindings -o yaml
kubectl --context=<ctx> get roles --all-namespaces -o yaml
kubectl --context=<ctx> get rolebindings --all-namespaces -o yaml
kubectl --context=<ctx> get serviceaccounts --all-namespaces -o yaml
```

**Manifest path:** run `grep -rlE 'kind:\s*(ClusterRole|Role|ClusterRoleBinding|RoleBinding|ServiceAccount)\b' <path>` then Read each match. Honor kustomize: if a `kustomization.yaml` is present, run `kubectl kustomize <dir>` (read-only render) to expand overlays before parsing.

### 2. Flag Dangerous Verbs

For every rule (`.rules[]` on ClusterRole/Role), emit a FINDING whenever any of these shapes is present. Severity in parentheses.

| Shape                                                    | Severity  |
| -------------------------------------------------------- | --------- |
| `verbs: ["*"]` on any resource                           | HIGH      |
| `verbs: contains "escalate"` on `clusterroles`/`roles`   | CRITICAL  |
| `verbs: contains "bind"` on `clusterroles`/`roles`       | CRITICAL  |
| `verbs: contains "impersonate"` on `users|groups|serviceaccounts` | CRITICAL |
| `verbs: contains "create"` on `pods/exec` or `pods/attach` | HIGH    |
| `verbs: ["*"]` on `secrets`                              | HIGH      |
| `verbs: ["get","list","watch"]` on `secrets` cluster-wide| MEDIUM    |
| `resources: ["*"]` with `apiGroups: ["*"]`               | HIGH      |
| `nonResourceURLs: ["*"]`                                 | MEDIUM    |

Record the role name, namespace (or `cluster`), resource, verbs, and the source object location (file+line if manifest; `kubectl` object ref if live).

### 3. Detect Escalation Paths

Walk the binding graph to identify two-step privilege escalation.

1. Build a map `subject -> [roles]` from all bindings.
2. For each ServiceAccount subject with a role containing `pods/exec` or `pods/attach`, enumerate pods in its namespace (`kubectl get pods -n <ns> -o yaml`) whose `spec.serviceAccountName` mounts a different SA that holds a higher-privilege role (`cluster-admin`, `*/*`, or `secrets *`). Emit FINDING `privesc-via-pod-exec`.
3. Any ClusterRoleBinding to `cluster-admin` where the subject is a non-system ServiceAccount → FINDING (CRITICAL) `cluster-admin-app-sa`.
4. Any subject with `roles/bind` or `roles/escalate` on ClusterRoles → FINDING (CRITICAL) `self-escalation`.

If pod enumeration is not permitted by the current kubeconfig, mark step 2 as INCONCLUSIVE but complete steps 1, 3, and 4.

### 4. Detect Over-Broad Subjects

For every binding, flag:

- `kind: Group, name: system:authenticated` on any non-read-only role → FINDING (CRITICAL).
- `kind: Group, name: system:unauthenticated` on anything → FINDING (CRITICAL).
- `kind: Group, name: system:masters` binding outside kube-system → FINDING (HIGH).
- Subjects referencing the `default` ServiceAccount in any namespace with anything beyond built-in `system:*` roles → FINDING (HIGH). Workloads should use dedicated SAs.
- Bindings whose `.subjects[].namespace` is missing when `kind: ServiceAccount` → FINDING (MEDIUM) `ambiguous-subject`.

### 5. Unused Roles

Compute the set of ClusterRoles and Roles that are defined but never referenced by a `roleRef` in any binding.

- Exclude built-in `system:*` roles and the aggregated `view`, `edit`, `admin`, `cluster-admin` roles.
- Exclude roles with the label `rbac.authorization.k8s.io/aggregate-to-*: "true"` since they are consumed by aggregation.
- Everything remaining → HOUSEKEEPING (low priority). Do not block the verdict on these.

## Output Format

```
## Kubernetes RBAC Audit — <context-or-path>

### Collection
- Source: live cluster (context=prod-gke)
- Objects: 412 ClusterRoles, 87 Roles, 531 ClusterRoleBindings, 203 RoleBindings, 1,204 ServiceAccounts

### Dangerous Verbs
| Severity  | Role                         | Scope        | Resource         | Verbs       |
| --------- | ---------------------------- | ------------ | ---------------- | ----------- |
| CRITICAL  | app-operator                 | cluster      | clusterroles     | [bind]      |
| HIGH      | ci-deployer                  | ns/ci        | pods/exec        | [create]    |
| HIGH      | platform-admin               | cluster      | secrets          | [*]         |

### Escalation Paths
- [CRITICAL] CRB `ci-admin` → sa:ci/runner → bound to `cluster-admin`
- [HIGH] sa:apps/webhook can exec into pods running sa:apps/db-client (reads DB secret)

### Over-Broad Subjects
| Severity  | Binding                    | Subject                         | Role         |
| --------- | -------------------------- | ------------------------------- | ------------ |
| CRITICAL  | CRB `open-read`            | Group system:authenticated      | view-secrets |

### Unused Roles (HOUSEKEEPING)
- Role `legacy-ingress-reader` in ns/legacy — no bindings
- ClusterRole `old-operator` — no bindings, not aggregated

**Verdict: NEEDS-REMEDIATION** (2 CRITICAL, 2 HIGH, 1 housekeeping)
```

## Verdict

- **CLEAN** — zero findings outside HOUSEKEEPING.
- **NEEDS-REMEDIATION** — one or more HIGH or MEDIUM findings.
- **CRITICAL** — any CRITICAL finding present.
- **INCONCLUSIVE** — neither live collection nor manifest parsing produced usable objects.

## Rules

1. **Read-only kubectl.** Only `kubectl get`, `kubectl describe`, `kubectl diff`, `kubectl config get-contexts`, `kubectl config current-context`, `kubectl config view`, and `kubectl kustomize` are permitted. Never call `apply`, `delete`, `patch`, `edit`, `create`, `replace`, `exec`, `cp`, `drain`, `cordon`, `uncordon`, `taint`, `label`, `annotate`, or `rollout`.
2. **Graceful skip.** Missing `kubectl`, unreachable API server, unset context, or forbidden verbs on a specific resource all resolve to SKIPPED for that step with the reason logged; other steps continue.
3. **Never fabricate.** Do not invent role names, namespace names, ServiceAccount names, binding names, or context names. When data is unavailable, emit INCONCLUSIVE.
4. **Respect kustomize/helm.** Render read-only via `kubectl kustomize`; do not attempt to render Helm charts that would execute post-render hooks. If only Helm sources are present and `helm template` is not safely available, emit SKIPPED for that tree.
5. **Cross-skill handoff.** This skill pairs with `/review-gke`, `/review-aws-iam`, and `/review-gcp-iam` for the cloud-side identity picture. Mention them in output when relevant; never invoke them.

$ARGUMENTS
