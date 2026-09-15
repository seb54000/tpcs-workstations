#!/usr/bin/env bash
set -euo pipefail

SCRIPT_START_SECONDS=$SECONDS

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform-infra"
POST_INSTALL_PLAYBOOK="$ROOT_DIR/post_install.yml"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-prepare-$(date +%Y%m%d-%H%M%S).log}"

print_usage() {
  cat <<EOF
Usage:
  $(basename "$0") <mode> [options]

Modes:
  full              Run Terraform then Ansible, same workflow as the previous default behavior.
  terraform, tf     Run only terraform init/apply.
  ansible           Run only ansible-playbook post_install.yml.
  ansible-opts, ansible_opts, ao
                    Run only ansible-playbook post_install.yml with extra Ansible options.
  help, -h, --help  Show this help.

Examples:
  $(basename "$0") full
  $(basename "$0") full -auto-approve

  $(basename "$0") tf -auto-approve
  $(basename "$0") tf -target=cloudflare_dns_record.student_vm[0] -target=aws_ec2_instance_state.student_vm[0]
  $(basename "$0") tf -target=cloudflare_dns_record.access[0] -target=aws_ec2_instance_state.access[0] -target=cloudflare_dns_record.docs[0]

  $(basename "$0") ansible
  $(basename "$0") ao -t student
  $(basename "$0") ao -t access_docs --start-at-task "Create parent directory for template files"
  $(basename "$0") ao -t student -t eks --limit "access,vm00,vm01,vm10"
  EKS_FORCE_ROTATE_TOKENS=true $(basename "$0") ao -t eks

Environment:
  CREDENTIALS_FILE  Defaults to $TF_DIR/credentials-setup.sh
  VENV_DIR          Defaults to $HOME/ansiblevenv
  LOG_FILE          Defaults to /tmp/tpcs-workstations-prepare-<timestamp>.log
EOF
}

if [[ "$#" -eq 0 ]]; then
  print_usage
  exit 0
fi

MODE="$1"
shift

case "$MODE" in
  full|terraform|tf|ansible|ansible-opts|ansible_opts|ao)
    ;;
  help|-h|--help)
    print_usage
    exit 0
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo
    print_usage
    exit 1
    ;;
esac

exec > >(tee -a "$LOG_FILE") 2>&1

format_duration() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  printf "%02dh %02dm %02ds" "$hours" "$minutes" "$seconds"
}

print_execution_summary() {
  local exit_code="$?"
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))

  echo
  echo "== Execution summary =="
  if [[ "$exit_code" -eq 0 ]]; then
    echo "Status: success"
  else
    echo "Status: failure (exit code: $exit_code)"
  fi
  echo "Total duration: $(format_duration "$elapsed_seconds")"
  echo "Log file: $LOG_FILE"
}

trap print_execution_summary EXIT

export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-true}"
export PY_COLORS="${PY_COLORS:-1}"
export CLICOLOR="${CLICOLOR:-1}"
export CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}"

echo "== tpcs-workstations prepare =="
echo "ROOT_DIR=$ROOT_DIR"
echo "CREDENTIALS_FILE=$CREDENTIALS_FILE"
echo "VENV_DIR=$VENV_DIR"
echo "LOG_FILE=$LOG_FILE"
echo "MODE=$MODE"

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
      "https://gitlab.multiseb.com/seb54000/tpcs-iac.git": $tpiac_branch,
      "https://gitlab.multiseb.com/seb54000/tp-cs-containers-student.git": $tpkube_branch,
      "https://gitlab.multiseb.com/seb54000/tp-cs-monitoring-student.git": $tpmon_branch,
      "https://gitlab.multiseb.com/seb54000/tpcs-demoboard.git": $demoboard_branch
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

run_terraform() {
  command -v terraform >/dev/null || { echo "terraform not found in PATH"; exit 1; }

  echo "Running terraform init/apply..."
  pushd "$TF_DIR" >/dev/null
  time terraform init
  time terraform apply "$@"
  popd >/dev/null
}

run_ansible() {
  command -v ansible-playbook >/dev/null || { echo "ansible-playbook not found in PATH"; exit 1; }

  echo "Running ansible post_install..."
  time ansible-playbook "$POST_INSTALL_PLAYBOOK" "${ansible_extra_args[@]}" "$@"
}

case "$MODE" in
  full)
    run_terraform "$@"
    run_ansible
    ;;
  terraform|tf)
    run_terraform "$@"
    ;;
  ansible)
    run_ansible
    ;;
  ansible-opts|ansible_opts|ao)
    run_ansible "$@"
    ;;
esac

echo "Prepare completed successfully."
