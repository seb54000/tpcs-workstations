#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform-infra"
POST_INSTALL_PLAYBOOK="$ROOT_DIR/post_install.yml"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-prepare-$(date +%Y%m%d-%H%M%S).log}"

exec > >(tee -a "$LOG_FILE") 2>&1

export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-true}"
export PY_COLORS="${PY_COLORS:-1}"
export CLICOLOR="${CLICOLOR:-1}"
export CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}"

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

echo "Validating Terraform credentials variables..."
echo "${TF_VAR_users_list:-}" | jq empty >/dev/null || {
  echo "Invalid TF_VAR_users_list JSON in $CREDENTIALS_FILE"
  exit 1
}
[[ "${TF_VAR_vm_number:-}" =~ ^[0-9]+$ ]] || {
  echo "Invalid TF_VAR_vm_number value after sourcing $CREDENTIALS_FILE: '${TF_VAR_vm_number:-}'"
  exit 1
}
if [[ -n "${TF_VAR_tp_names:-}" ]]; then
  echo "${TF_VAR_tp_names}" | jq -e '
    type == "array"
    and all(.[]; . == "tpiac" or . == "tpkube" or . == "tpmon")
  ' >/dev/null || {
    echo "Invalid TF_VAR_tp_names JSON in $CREDENTIALS_FILE. Expected an array containing only tpiac, tpkube or tpmon."
    exit 1
  }
fi

student_git_branch_overrides_json="$(
  jq -cn \
    --arg tpiac_branch "${STUDENT_TPIAC_GIT_BRANCH:-}" \
    --arg tpkube_branch "${STUDENT_TPKUBE_GIT_BRANCH:-}" \
    --arg tpmon_branch "${STUDENT_TPMON_GIT_BRANCH:-}" \
    --arg demoboard_branch "${STUDENT_DEMOBOARD_GIT_BRANCH:-}" \
    '{
      "https://github.com/seb54000/tpcs-iac.git": $tpiac_branch,
      "https://github.com/seb54000/tp-cs-containers-student.git": $tpkube_branch,
      "https://github.com/seb54000/tp-cs-monitoring-student.git": $tpmon_branch,
      "https://github.com/seb54000/tpcs-demoboard.git": $demoboard_branch
    } | with_entries(select(.value != ""))'
)"

ansible_extra_args=()
if [[ "$student_git_branch_overrides_json" != "{}" ]]; then
  echo "Using student git branch overrides: $student_git_branch_overrides_json"
  ansible_extra_args+=(
    -e
    "{\"student_git_branch_overrides\":$student_git_branch_overrides_json}"
  )
fi

echo "Activating venv..."
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

command -v terraform >/dev/null || { echo "terraform not found in PATH"; exit 1; }
command -v ansible-playbook >/dev/null || { echo "ansible-playbook not found in PATH"; exit 1; }

echo "Running terraform init/apply..."
pushd "$TF_DIR" >/dev/null
time terraform init
time terraform apply "$@"
popd >/dev/null

echo "Running ansible post_install..."
time ansible-playbook "$POST_INSTALL_PLAYBOOK" "${ansible_extra_args[@]}"

echo "Prepare completed successfully."
echo "Log file: $LOG_FILE"
