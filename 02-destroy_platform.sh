#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform-infra"
LB_CLEANUP_SCRIPT="$TF_DIR/scripts/09_cleanup_eks_loadbalancers_before_destroy.sh"
PV_CLEANUP_SCRIPT="$TF_DIR/scripts/10_cleanup_eks_persistent_volumes_before_destroy.sh"
TPIAC_DESTROY_SCRIPT="$TF_DIR/scripts/08_tpiac_terraform_destroy_everywhere.sh"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-destroy-$(date +%Y%m%d-%H%M%S).log}"
FORCE_ORPHAN_DELETE="${FORCE_ORPHAN_DELETE:-true}"
TPIAC_DESTROY_CONFIRMATION="${TPIAC_DESTROY_CONFIRMATION:-}"

exec > >(tee -a "$LOG_FILE") 2>&1

export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-true}"
export PY_COLORS="${PY_COLORS:-1}"
export CLICOLOR="${CLICOLOR:-1}"
export CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}"

echo "== tpcs-workstations destroy =="
echo "ROOT_DIR=$ROOT_DIR"
echo "CREDENTIALS_FILE=$CREDENTIALS_FILE"
echo "VENV_DIR=$VENV_DIR"
echo "FORCE_ORPHAN_DELETE=$FORCE_ORPHAN_DELETE"
echo "LOG_FILE=$LOG_FILE"

tp_iac_is_enabled() {
  if [[ "${TF_VAR_tp_name:-}" == "tpiac" ]]; then
    return 0
  fi

  if [[ -n "${TF_VAR_tp_names:-}" ]]; then
    [[ "$TF_VAR_tp_names" == *'"tpiac"'* ]]
    return
  fi

  return 1
}

confirm_tpiac_student_destroy_done() {
  if ! tp_iac_is_enabled; then
    return 0
  fi

  if [[ ! -x "$TPIAC_DESTROY_SCRIPT" ]]; then
    echo "TP IaC cleanup script not found or not executable: $TPIAC_DESTROY_SCRIPT"
    exit 1
  fi

  cat <<EOF_WARNING

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!! WARNING - TP IaC resources must be destroyed from student VMs first
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

This platform includes TP IaC.

Before destroying the student VMs, you must make sure that Terraform destroy has
been run for every Terraform state left on every student VM.

If you destroy the student VMs first, their local tfstate files disappear and
AWS resources created by students can become orphaned. Cleaning them manually is
slow and error-prone: EC2 instances, load balancers, volumes, VPC resources,
security groups, gateways, and other leftovers may remain in multiple regions.

Run these commands before continuing:

  cd "$TF_DIR"
  ./scripts/08_tpiac_terraform_destroy_everywhere.sh AUDIT
  ./scripts/08_tpiac_terraform_destroy_everywhere.sh DELETE
  ./scripts/08_tpiac_terraform_destroy_everywhere.sh AUDIT

Continue only if the final AUDIT is clean or if you deliberately accept the
remaining resources.

EOF_WARNING

  local expected="I_HAVE_RUN_TPIAC_STUDENT_TERRAFORM_DESTROY"
  if [[ "$TPIAC_DESTROY_CONFIRMATION" == "$expected" ]]; then
    echo "TP IaC destroy confirmation accepted from TPIAC_DESTROY_CONFIRMATION."
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "Non-interactive shell detected."
    echo "Set TPIAC_DESTROY_CONFIRMATION=$expected only after running the TP IaC cleanup commands."
    exit 1
  fi

  local answer
  read -r -p "Type '$expected' to continue destroying the student VMs: " answer
  if [[ "$answer" != "$expected" ]]; then
    echo "Destroy aborted. Run the TP IaC cleanup commands first."
    exit 1
  fi
}

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Missing credentials file: $CREDENTIALS_FILE"
  exit 1
fi

if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
  echo "Missing venv activate script: $VENV_DIR/bin/activate"
  exit 1
fi

if [[ ! -x "$LB_CLEANUP_SCRIPT" ]]; then
  echo "Cleanup script not found or not executable: $LB_CLEANUP_SCRIPT"
  exit 1
fi

if [[ ! -x "$PV_CLEANUP_SCRIPT" ]]; then
  echo "Cleanup script not found or not executable: $PV_CLEANUP_SCRIPT"
  exit 1
fi

# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"
confirm_tpiac_student_destroy_done
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

command -v terraform >/dev/null || { echo "terraform not found in PATH"; exit 1; }

echo "Capturing current terraform outputs for cleanup helpers..."
pushd "$TF_DIR" >/dev/null
TF_OUTPUT_JSON_CACHE="$(terraform output -json)"
popd >/dev/null
export TF_OUTPUT_JSON_CACHE

echo "Running EKS LB cleanup..."
FORCE_ORPHAN_DELETE="$FORCE_ORPHAN_DELETE" "$LB_CLEANUP_SCRIPT"

echo "Running EKS AWS EBS PVC/CSI cleanup..."
FORCE_ORPHAN_DELETE="$FORCE_ORPHAN_DELETE" "$PV_CLEANUP_SCRIPT"

echo "Running terraform init/destroy..."
pushd "$TF_DIR" >/dev/null
time terraform init
time terraform destroy "$@"
popd >/dev/null

echo "Running final AWS EBS PVC/CSI cleanup after terraform destroy..."
FORCE_ORPHAN_DELETE="$FORCE_ORPHAN_DELETE" "$PV_CLEANUP_SCRIPT" || true

echo "Destroy completed successfully."
echo "Log file: $LOG_FILE"
