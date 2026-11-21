#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_START_SECONDS=$SECONDS
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$ROOT_DIR/terraform-infra/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-image-$(date +%Y%m%d-%H%M%S).log}"
PYTHON_TOOL="$ROOT_DIR/scripts/tpcs_images.py"

print_usage() {
  cat <<'EOF'
Usage:
  ./00-build-image.sh build [--profile student-tpiac|access-docs] [--generation NAME] [--account ECOLE|PERSO] [--yes]
  ./00-build-image.sh backup --ami-id ami-... [--generation NAME] [--profile PROFILE] [--account ECOLE|PERSO] [--yes]
  ./00-build-image.sh restore --profile PROFILE --generation NAME [--account ECOLE|PERSO] [--yes]
  ./00-build-image.sh delete (--current | --generation NAME | --ami-id ami-...) [--profile PROFILE] [--account ECOLE|PERSO] [--yes]
  ./00-build-image.sh list nas
  ./00-build-image.sh list aws [--account ECOLE|PERSO|all]
  ./00-build-image.sh check [--max-age-days 21] [--account ECOLE|PERSO|all]

build creates a NAS generation automatically, exports it, and removes its temporary
AMI from AWS. Profiles are student-tpiac and access-docs; --generation is an
optional version label. restore uploads one selected generation into its fixed AWS
current-image slot, replacing previous images for that profile.

AWS operations use TPCS_AWS_ACCOUNT from the private credentials file unless
--account overrides it. list aws/check inspect both accounts by default. Terraform
looks up fixed current-image names when TF_VAR_ami_source=packer; missing images
fall back to standard Ubuntu with a Terraform check warning. Existing VM AMI IDs
are ignored on later applies. delete refuses AMIs referenced by non-terminated
instances unless --force-in-use is explicitly supplied. It never terminates instances.

Optional environment:
  CREDENTIALS_FILE  Private credentials file; defaults to terraform-infra/credentials-setup.sh.
  VENV_DIR          Ansible virtual environment used by the Packer build.
  LOG_FILE          Log destination; defaults to /tmp/tpcs-workstations-image-<timestamp>.log.
EOF
}

format_duration() {
  local total_seconds="$1"
  printf '%02dm %02ds' "$((total_seconds / 60))" "$((total_seconds % 60))"
}

print_summary() {
  local exit_code="$?"
  echo
  echo "== TPCS image operation summary =="
  if [[ "$exit_code" -eq 0 ]]; then
    echo "Status: success"
  else
    echo "Status: failure (exit code: $exit_code)"
  fi
  echo "Duration: $(format_duration "$((SECONDS - SCRIPT_START_SECONDS))")"
  echo "Log file: $LOG_FILE"
}

if [[ $# -eq 0 || "$1" == --help || "$1" == -h || "$1" == help ]]; then
  print_usage
  exit 0
fi

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Missing credentials file: $CREDENTIALS_FILE" >&2
  exit 1
fi

exec > >(tee -a "$LOG_FILE") 2>&1
trap print_summary EXIT
echo "LOG_FILE=$LOG_FILE"

source "$ROOT_DIR/scripts/tpcs-credentials.sh"
tpcs_source_credentials "$CREDENTIALS_FILE"

ACTION="$1"
shift
ACCOUNT="${TPCS_AWS_ACCOUNT_ACTIVE:-ECOLE}"
ACCOUNT_EXPLICIT=false
TOOL_ARGS=()
while (($#)); do
  case "$1" in
    --account)
      (($# >= 2)) || { echo "--account requires ECOLE, PERSO or all." >&2; exit 2; }
      ACCOUNT="${2^^}"
      ACCOUNT_EXPLICIT=true
      shift 2
      ;;
    --account=*)
      ACCOUNT="${1#*=}"
      ACCOUNT="${ACCOUNT^^}"
      ACCOUNT_EXPLICIT=true
      shift
      ;;
    *)
      TOOL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "$ACCOUNT" == ALL ]]; then
  ACCOUNT=all
fi
if [[ "$ACCOUNT_EXPLICIT" == false && \
      ( "$ACTION" == check || ( "$ACTION" == list && "${TOOL_ARGS[0]:-}" == aws ) ) ]]; then
  ACCOUNT=all
fi

if [[ "$ACTION" == list && "${TOOL_ARGS[0]:-}" == nas ]]; then
  [[ "$ACCOUNT" != all ]] || { echo "list nas does not take --account all." >&2; exit 2; }
  python3 -u "$PYTHON_TOOL" list nas
  exit $?
fi

if [[ "$ACTION" == build ]]; then
  if [[ -f "$VENV_DIR/bin/activate" ]]; then
    # shellcheck source=/dev/null
    source "$VENV_DIR/bin/activate"
  fi
  command -v ansible-playbook >/dev/null || {
    echo "ansible-playbook not found; activate/install the TP Ansible environment or set VENV_DIR." >&2
    exit 1
  }
fi

if [[ "$ACCOUNT" == all ]]; then
  if ! { [[ "$ACTION" == check ]] || [[ "$ACTION" == list && "${TOOL_ARGS[0]:-}" == aws ]]; }; then
    echo "--account all is supported only by list aws and check." >&2
    exit 2
  fi
  has_findings=false
  fatal_status=0
  for account in ECOLE PERSO; do
    tpcs_select_aws_account "$account"
    echo "===== AWS account scan: $account ====="
    if python3 -u "$PYTHON_TOOL" "$ACTION" "${TOOL_ARGS[@]}" --account "$account"; then
      :
    else
      status=$?
      if [[ "$ACTION" == check && "$status" -eq 1 ]]; then
        has_findings=true
      else
        fatal_status="$status"
      fi
    fi
  done
  if ((fatal_status != 0)); then
    exit "$fatal_status"
  fi
  [[ "$has_findings" == true ]] && exit 1 || exit 0
fi

case "$ACCOUNT" in
  ECOLE|PERSO) ;;
  *) echo "Account must be ECOLE, PERSO or all." >&2; exit 2 ;;
esac
tpcs_select_aws_account "$ACCOUNT"
python3 -u "$PYTHON_TOOL" "$ACTION" "${TOOL_ARGS[@]}" --account "$ACCOUNT"
