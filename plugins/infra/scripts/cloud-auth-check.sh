#!/usr/bin/env bash
# cloud-auth-check.sh — Probe cloud-provider CLI authentication without making changes.
#
# Used by all infra review/triage skills as step 1 to report consistent SKIPPED
# behavior when a CLI is missing or credentials are absent/expired.
#
# Usage:
#   cloud-auth-check.sh aws
#   cloud-auth-check.sh gcp
#   cloud-auth-check.sh kubectl
#   cloud-auth-check.sh all
#
# Output (stdout, single-line JSON per provider, or object with all when "all"):
#   { "provider": "aws",     "status": "OK"|"MISSING_CLI"|"UNAUTHENTICATED"|"EXPIRED",
#     "identity": "<arn|project|context>"|null,
#     "detail":   "<human-readable reason>" }
#
# Exit codes:
#   0 — probe completed (status may be any label above)
#   2 — unknown provider argument
#
# No mutating calls are made. AWS probe uses `sts get-caller-identity`.
# GCP probe uses `gcloud auth list` + `gcloud config get-value project`.
# kubectl probe uses `kubectl config current-context` + `kubectl version --request-timeout=2s`.

set -u

emit() {
  local provider="$1" status="$2" identity="$3" detail="$4"
  # Escape double quotes and backslashes in identity/detail.
  esc() { local v="$1"; v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; printf '%s' "$v"; }
  local ident_field="null"
  if [ "$identity" != "__NULL__" ]; then
    ident_field="\"$(esc "$identity")\""
  fi
  printf '{"provider":"%s","status":"%s","identity":%s,"detail":"%s"}\n' \
    "$provider" "$status" "$ident_field" "$(esc "$detail")"
}

check_aws() {
  if ! command -v aws >/dev/null 2>&1; then
    emit "aws" "MISSING_CLI" "__NULL__" "aws CLI not found on PATH"
    return
  fi
  local out rc
  out=$(aws sts get-caller-identity --output text --query 'Arn' 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    if printf '%s' "$out" | grep -qiE 'expired|token has expired|ExpiredToken'; then
      emit "aws" "EXPIRED" "__NULL__" "AWS credentials expired: $out"
    else
      emit "aws" "UNAUTHENTICATED" "__NULL__" "sts get-caller-identity failed: $out"
    fi
    return
  fi
  emit "aws" "OK" "$out" "authenticated"
}

check_gcp() {
  if ! command -v gcloud >/dev/null 2>&1; then
    emit "gcp" "MISSING_CLI" "__NULL__" "gcloud CLI not found on PATH"
    return
  fi
  local active
  active=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
  if [ -z "$active" ]; then
    emit "gcp" "UNAUTHENTICATED" "__NULL__" "no active gcloud account (run: gcloud auth login)"
    return
  fi
  local project
  project=$(gcloud config get-value project 2>/dev/null | head -n1)
  if [ -z "$project" ] || [ "$project" = "(unset)" ]; then
    emit "gcp" "UNAUTHENTICATED" "$active" "account active but no project set (run: gcloud config set project <id>)"
    return
  fi
  emit "gcp" "OK" "${active} @ ${project}" "authenticated"
}

check_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    emit "kubectl" "MISSING_CLI" "__NULL__" "kubectl not found on PATH"
    return
  fi
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null)
  if [ -z "$ctx" ]; then
    emit "kubectl" "UNAUTHENTICATED" "__NULL__" "no current kubectl context"
    return
  fi
  # Short timeout probe against the cluster — read-only.
  local out rc
  out=$(kubectl version --request-timeout=2s --output=json 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    emit "kubectl" "UNAUTHENTICATED" "$ctx" "context set but cluster unreachable: $(printf '%s' "$out" | head -n1)"
    return
  fi
  emit "kubectl" "OK" "$ctx" "context set and cluster reachable"
}

case "${1:-}" in
  aws)     check_aws ;;
  gcp)     check_gcp ;;
  kubectl) check_kubectl ;;
  all)
    printf '{'
    printf '"aws":'; check_aws | tr -d '\n'; printf ','
    printf '"gcp":'; check_gcp | tr -d '\n'; printf ','
    printf '"kubectl":'; check_kubectl | tr -d '\n'
    printf '}\n'
    ;;
  *)
    printf 'usage: cloud-auth-check.sh {aws|gcp|kubectl|all}\n' >&2
    exit 2
    ;;
esac
