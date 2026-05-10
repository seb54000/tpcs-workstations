#!/usr/bin/env bash
set -u
set -o pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 {AUDIT|DELETE}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
KEY_FILE="${KEY_FILE:-$TF_DIR/key}"

# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

ACTION="$1"
DNS_SUBDOMAIN="${TF_VAR_dns_subdomain:-tpcsonline.org}"
VM_COUNT="${TF_VAR_vm_number:-0}"

ssh_base=(
  ssh
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o BatchMode=yes
  -o ConnectTimeout=10
  -i "$KEY_FILE"
)

if [[ ! "$VM_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Invalid TF_VAR_vm_number: '$VM_COUNT'"
  exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing SSH key file: $KEY_FILE"
  exit 1
fi

remote_audit_command=$(cat <<'EOF'
set -u
echo "CONNECTED host=$(hostname) user=$(whoami) cwd=$(pwd)"

if [[ -f "$HOME/tpcs-iac/.env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/tpcs-iac/.env"
  echo "ENV loaded: $HOME/tpcs-iac/.env"
else
  echo "ENV missing: $HOME/tpcs-iac/.env"
fi

if command -v aws >/dev/null 2>&1; then
  region="$(aws configure get region 2>/dev/null || true)"
  identity="$(aws sts get-caller-identity --output text --query 'Arn' 2>/dev/null || true)"
  echo "AWS region=${region:-N/A} identity=${identity:-N/A}"
else
  echo "AWS CLI missing"
fi

if command -v terraform >/dev/null 2>&1; then
  terraform version | head -n 1
else
  echo "Terraform missing"
fi

mapfile -t tfstates < <(sudo find / -type f -name "terraform.tfstate" -size +200c -exec ls -lh {} ';' 2>/dev/null)
echo "TFSTATE_COUNT=${#tfstates[@]}"
if [[ ${#tfstates[@]} -gt 0 ]]; then
  printf '%s\n' "${tfstates[@]}"
fi
EOF
)

remote_delete_command=$(cat <<'EOF'
set -u
echo "CONNECTED host=$(hostname) user=$(whoami) cwd=$(pwd)"

if [[ -f "$HOME/tpcs-iac/.env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/tpcs-iac/.env"
  echo "ENV loaded: $HOME/tpcs-iac/.env"
else
  echo "ENV missing: $HOME/tpcs-iac/.env"
fi

if command -v aws >/dev/null 2>&1; then
  region="$(aws configure get region 2>/dev/null || true)"
  identity="$(aws sts get-caller-identity --output text --query 'Arn' 2>/dev/null || true)"
  echo "AWS region=${region:-N/A} identity=${identity:-N/A}"
fi

mapfile -t tfstate_paths < <(sudo find / -type f -name "terraform.tfstate" -size +200c 2>/dev/null)
echo "TFSTATE_COUNT=${#tfstate_paths[@]}"

if [[ ${#tfstate_paths[@]} -eq 0 ]]; then
  exit 0
fi

for tfstate in "${tfstate_paths[@]}"; do
  dir="$(dirname "$tfstate")"
  echo "Found state file: $tfstate"
  echo "Running terraform destroy -auto-approve in $dir"
  cd "$dir" || {
    echo "Cannot cd to $dir"
    continue
  }
  terraform init -input=false
  terraform destroy -auto-approve
done
EOF
)

run_for_vm() {
  local digits="$1"
  local host="vm${digits}.${DNS_SUBDOMAIN}"
  local user="vm${digits}"
  local remote_command="$2"

  echo "===== vm${digits} (${user}@${host}) ====="
  if ! "${ssh_base[@]}" "${user}@${host}" "$remote_command" 2>&1 | sed "s/^/[vm${digits}] /"; then
    echo "[vm${digits}] SSH_OR_REMOTE_FAILED"
    return 1
  fi
  echo "[vm${digits}] DONE"
}

case "$ACTION" in
  AUDIT)
    echo ">>> Mode AUDIT"
    echo "VM_COUNT=$VM_COUNT"
    echo "DNS_SUBDOMAIN=$DNS_SUBDOMAIN"
    echo "KEY_FILE=$KEY_FILE"
    failed=0
    for ((i = 0; i < VM_COUNT; i++)); do
      digits="$(printf "%02d" "$i")"
      run_for_vm "$digits" "$remote_audit_command" || failed=1
    done
    if [[ "$failed" -ne 0 ]]; then
      echo "AUDIT completed with at least one SSH or remote command failure."
      exit 1
    fi
    echo "AUDIT completed."
    ;;

  DELETE)
    echo ">>> Mode DELETE"
    echo "VM_COUNT=$VM_COUNT"
    echo "DNS_SUBDOMAIN=$DNS_SUBDOMAIN"
    echo "KEY_FILE=$KEY_FILE"
    failed=0
    for ((i = 0; i < VM_COUNT; i++)); do
      digits="$(printf "%02d" "$i")"
      run_for_vm "$digits" "$remote_delete_command" || failed=1
    done
    if [[ "$failed" -ne 0 ]]; then
      echo "DELETE completed with at least one SSH or remote command failure."
      exit 1
    fi
    echo "DELETE completed."
    ;;

  *)
    echo "Invalid argument: $ACTION"
    echo "Usage: $0 {AUDIT|DELETE}"
    exit 1
    ;;
esac
