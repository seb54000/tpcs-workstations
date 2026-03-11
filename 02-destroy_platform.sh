#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform-infra"
CLEANUP_SCRIPT="$TF_DIR/scripts/09_cleanup_eks_loadbalancers_before_destroy.sh"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-destroy-$(date +%Y%m%d-%H%M%S).log}"
FORCE_ORPHAN_DELETE="${FORCE_ORPHAN_DELETE:-false}"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "== tpcs-workstations destroy =="
echo "ROOT_DIR=$ROOT_DIR"
echo "CREDENTIALS_FILE=$CREDENTIALS_FILE"
echo "VENV_DIR=$VENV_DIR"
echo "FORCE_ORPHAN_DELETE=$FORCE_ORPHAN_DELETE"
echo "LOG_FILE=$LOG_FILE"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Missing credentials file: $CREDENTIALS_FILE"
  exit 1
fi

if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
  echo "Missing venv activate script: $VENV_DIR/bin/activate"
  exit 1
fi

if [[ ! -x "$CLEANUP_SCRIPT" ]]; then
  echo "Cleanup script not found or not executable: $CLEANUP_SCRIPT"
  exit 1
fi

# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

command -v terraform >/dev/null || { echo "terraform not found in PATH"; exit 1; }

echo "Running EKS LB cleanup..."
FORCE_ORPHAN_DELETE="$FORCE_ORPHAN_DELETE" "$CLEANUP_SCRIPT"

echo "Running terraform init/destroy..."
pushd "$TF_DIR" >/dev/null
time terraform init
time terraform destroy "$@"
popd >/dev/null

echo "Destroy completed successfully."
echo "Log file: $LOG_FILE"
