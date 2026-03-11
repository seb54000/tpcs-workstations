#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform-infra"
POST_INSTALL_PLAYBOOK="$ROOT_DIR/post_install.yml"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-prepare-$(date +%Y%m%d-%H%M%S).log}"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "== tpcs-workstations prepare =="
echo "ROOT_DIR=$ROOT_DIR"
echo "CREDENTIALS_FILE=$CREDENTIALS_FILE"
echo "VENV_DIR=$VENV_DIR"
echo "LOG_FILE=$LOG_FILE"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Missing credentials file: $CREDENTIALS_FILE"
  exit 1
fi

if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
  echo "Missing venv activate script: $VENV_DIR/bin/activate"
  exit 1
fi

echo "Sourcing credentials..."
# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

echo "Activating venv..."
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

command -v terraform >/dev/null || { echo "terraform not found in PATH"; exit 1; }
command -v ansible-playbook >/dev/null || { echo "ansible-playbook not found in PATH"; exit 1; }

echo "Running terraform init/apply..."
pushd "$TF_DIR" >/dev/null
time terraform init
time terraform apply
popd >/dev/null

echo "Running ansible post_install..."
time ansible-playbook "$POST_INSTALL_PLAYBOOK"

echo "Prepare completed successfully."
echo "Log file: $LOG_FILE"
