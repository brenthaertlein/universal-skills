#!/usr/bin/env bash
# detect-iac-scope.sh — Emit a JSON description of IaC artifacts in the current repo.
#
# Shared by: preflight, review-drift, review-costs, assess-change-risk,
#            review-disaster-recovery, review-observability, review-ansible-playbooks.
#
# Output (stdout, single-line JSON):
#   {
#     "root": "<repo-root>",
#     "terraform":    {"present": bool, "modules":  [paths]},
#     "pulumi":       {"present": bool, "stacks":   [paths]},
#     "cloudformation":{"present":bool, "templates":[paths]},
#     "ansible":      {"present": bool, "roles":    [paths], "playbooks":[paths], "inventory":[paths]},
#     "kubernetes":   {"present": bool, "manifests":[paths], "kustomize":[paths]},
#     "helm":         {"present": bool, "charts":   [paths]},
#     "docker_compose":{"present":bool, "files":    [paths]}
#   }
#
# Exit codes:
#   0 — success (even if nothing detected — the JSON will say so)
#   1 — unexpected error (not missing tools; just bugs)
#
# Usage:
#   detect-iac-scope.sh                    # scan current directory
#   detect-iac-scope.sh /path/to/repo      # scan a specific path
#
# No external tools required — pure bash + find.

set -euo pipefail

root="${1:-$(pwd)}"
root="$(cd "$root" && pwd)"

# Collect matching paths into a JSON array. Emits [] when nothing matches.
# Args: NAME, find-pattern(s)
json_array() {
  local -a paths=()
  while IFS= read -r p; do paths+=("$p"); done < <(
    find "$root" \
      \( -path '*/node_modules' -o -path '*/.git' -o -path '*/.terraform' -o -path '*/vendor' \) -prune \
      -o -type f "$@" -print 2>/dev/null | sort
  )
  if [ "${#paths[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '['
    local first=1
    for p in "${paths[@]}"; do
      rel="${p#"$root"/}"
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      # Minimal JSON escape: backslash, quote, control chars (we don't expect control chars in paths)
      esc="${rel//\\/\\\\}"; esc="${esc//\"/\\\"}"
      printf '"%s"' "$esc"
    done
    printf ']'
  fi
}

# Same but for directories.
json_array_dirs() {
  local -a paths=()
  while IFS= read -r p; do paths+=("$p"); done < <(
    find "$root" \
      \( -path '*/node_modules' -o -path '*/.git' -o -path '*/.terraform' -o -path '*/vendor' \) -prune \
      -o -type d "$@" -print 2>/dev/null | sort -u
  )
  if [ "${#paths[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '['
    local first=1
    for p in "${paths[@]}"; do
      rel="${p#"$root"/}"
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      esc="${rel//\\/\\\\}"; esc="${esc//\"/\\\"}"
      printf '"%s"' "$esc"
    done
    printf ']'
  fi
}

# --- Terraform ---
tf_modules=$(json_array_dirs -name '*.tf' -printf '%h\n' 2>/dev/null || find "$root" -type f -name '*.tf' -exec dirname {} \; 2>/dev/null | sort -u | awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0}END{printf "]"}')
# Fallback (portable): collect dirs containing *.tf.
tf_dirs=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' -o -path '*/.terraform' -o -path '*/vendor' \) -prune \
  -o -type f \( -name '*.tf' -o -name '*.tfvars' -o -name '*.tfvars.json' \) -print 2>/dev/null \
  | while IFS= read -r f; do dirname "$f"; done | sort -u)
tf_present=false
tf_json='[]'
if [ -n "$tf_dirs" ]; then
  tf_present=true
  tf_json='['
  first=1
  while IFS= read -r d; do
    rel="${d#"$root"/}"
    esc="${rel//\\/\\\\}"; esc="${esc//\"/\\\"}"
    if [ $first -eq 1 ]; then first=0; else tf_json+=','; fi
    tf_json+="\"$esc\""
  done <<< "$tf_dirs"
  tf_json+=']'
fi

# --- Pulumi ---
pulumi_files=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type f -name 'Pulumi.yaml' -print 2>/dev/null | sort)
pulumi_present=false
pulumi_json='[]'
if [ -n "$pulumi_files" ]; then
  pulumi_present=true
  pulumi_json='['
  first=1
  while IFS= read -r f; do
    d=$(dirname "$f"); rel="${d#"$root"/}"
    esc="${rel//\\/\\\\}"; esc="${esc//\"/\\\"}"
    if [ $first -eq 1 ]; then first=0; else pulumi_json+=','; fi
    pulumi_json+="\"$esc\""
  done <<< "$pulumi_files"
  pulumi_json+=']'
fi

# --- CloudFormation ---
cfn_files=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type f \( -name '*.template.yaml' -o -name '*.template.yml' -o -name '*.template.json' -o -name 'cfn-*.yaml' -o -name 'cfn-*.yml' \) -print 2>/dev/null | sort)
cfn_present=false
cfn_json='[]'
if [ -n "$cfn_files" ]; then
  cfn_present=true
  cfn_json='['
  first=1
  while IFS= read -r f; do
    rel="${f#"$root"/}"
    esc="${rel//\\/\\\\}"; esc="${esc//\"/\\\"}"
    if [ $first -eq 1 ]; then first=0; else cfn_json+=','; fi
    cfn_json+="\"$esc\""
  done <<< "$cfn_files"
  cfn_json+=']'
fi

# --- Ansible ---
ansible_roles=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type d -name 'tasks' -print 2>/dev/null | while IFS= read -r d; do
    parent=$(dirname "$d")
    gparent=$(dirname "$parent")
    # A role looks like .../roles/<role-name>/tasks/
    if [ "$(basename "$gparent")" = "roles" ]; then echo "$parent"; fi
  done | sort -u)
ansible_playbooks=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type f \( -name 'playbook*.yml' -o -name 'playbook*.yaml' -o -path '*/playbooks/*.yml' -o -path '*/playbooks/*.yaml' \) -print 2>/dev/null | sort)
ansible_inventory=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o \( -type d -name 'inventory' -o -type f -name 'hosts' -o -type f -name 'inventory.ini' -o -type f -name 'inventory.yml' \) -print 2>/dev/null | sort)
ansible_present=false
if [ -n "$ansible_roles$ansible_playbooks$ansible_inventory" ]; then ansible_present=true; fi

to_json_lines() {
  local input="$1"
  local out='['
  local first=1
  if [ -n "$input" ]; then
    while IFS= read -r line; do
      rel="${line#"$root"/}"
      esc="${rel//\\/\\\\}"; esc="${esc//\"/\\\"}"
      if [ $first -eq 1 ]; then first=0; else out+=','; fi
      out+="\"$esc\""
    done <<< "$input"
  fi
  out+=']'
  printf '%s' "$out"
}
ansible_roles_json=$(to_json_lines "$ansible_roles")
ansible_playbooks_json=$(to_json_lines "$ansible_playbooks")
ansible_inventory_json=$(to_json_lines "$ansible_inventory")

# --- Kubernetes manifests + kustomize ---
kustomize_files=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type f -name 'kustomization.yaml' -print 2>/dev/null | sort)
k8s_dirs=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' -o -path '*/vendor' \) -prune \
  -o -type d \( -name 'k8s' -o -name 'kubernetes' -o -name 'manifests' \) -print 2>/dev/null | sort)
k8s_present=false
if [ -n "$kustomize_files$k8s_dirs" ]; then k8s_present=true; fi
k8s_manifests_json=$(to_json_lines "$k8s_dirs")
kustomize_json=$(to_json_lines "$kustomize_files")

# --- Helm ---
helm_charts=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type f -name 'Chart.yaml' -print 2>/dev/null | while IFS= read -r f; do dirname "$f"; done | sort -u)
helm_present=false
[ -n "$helm_charts" ] && helm_present=true
helm_json=$(to_json_lines "$helm_charts")

# --- Docker Compose ---
compose_files=$(find "$root" \
  \( -path '*/node_modules' -o -path '*/.git' \) -prune \
  -o -type f \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) -print 2>/dev/null | sort)
compose_present=false
[ -n "$compose_files" ] && compose_present=true
compose_json=$(to_json_lines "$compose_files")

# Emit final JSON.
printf '{"root":"%s","terraform":{"present":%s,"modules":%s},"pulumi":{"present":%s,"stacks":%s},"cloudformation":{"present":%s,"templates":%s},"ansible":{"present":%s,"roles":%s,"playbooks":%s,"inventory":%s},"kubernetes":{"present":%s,"manifests":%s,"kustomize":%s},"helm":{"present":%s,"charts":%s},"docker_compose":{"present":%s,"files":%s}}\n' \
  "${root//\\/\\\\}" \
  "$tf_present" "$tf_json" \
  "$pulumi_present" "$pulumi_json" \
  "$cfn_present" "$cfn_json" \
  "$ansible_present" "$ansible_roles_json" "$ansible_playbooks_json" "$ansible_inventory_json" \
  "$k8s_present" "$k8s_manifests_json" "$kustomize_json" \
  "$helm_present" "$helm_json" \
  "$compose_present" "$compose_json"
