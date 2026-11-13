#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_START_SECONDS=$SECONDS

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$ROOT_DIR/packer"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$ROOT_DIR/terraform-infra/credentials-setup.sh}"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
LOG_FILE="${LOG_FILE:-/tmp/tpcs-workstations-packer-$(date +%Y%m%d-%H%M%S).log}"
AUTO_APPROVE=false

print_usage() {
  cat <<EOF
Usage:
  ./0-build-image.sh [--yes]

Builds the student workstation AMI in AWS using Packer and the shared Ansible
package tasks. On success, writes the AMI id to
terraform-infra/packer-student.auto.tfvars.json for Terraform to consume.

Options:
  --yes, -y  Skip the final confirmation before launching the temporary EC2 build.
  --help     Show this help.

Optional variables in credentials-setup.sh:
  TPCS_PACKER_BUILD_REGION        Defaults to AWS_DEFAULT_REGION, then eu-west-3.
  TPCS_PACKER_SOURCE_AMI          Defaults to the current student source AMI.
  TPCS_PACKER_BUILD_INSTANCE_TYPE Defaults to m5.large.
  TPCS_PACKER_SUBNET_ID           Optional public subnet if the account has no default VPC.
  TPCS_PACKER_AMI_NAME_PREFIX     Defaults to tpcs-student-jammy.
  LOG_FILE                        Defaults to /tmp/tpcs-workstations-packer-<timestamp>.log.

Select the generated image for later Terraform applies with:
  export TF_VAR_student_ami_source=packer
The default is standard; set it back to standard to use the current Ubuntu AMI.
EOF
}

while (($#)); do
  case "$1" in
    --yes|-y) AUTO_APPROVE=true ;;
    --help|-h) print_usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
  shift
done

exec > >(tee -a "$LOG_FILE") 2>&1

format_duration() {
  local total_seconds="$1"
  local minutes=$((total_seconds / 60))
  local seconds=$((total_seconds % 60))
  printf "%02dm %02ds" "$minutes" "$seconds"
}

print_execution_summary() {
  local exit_code="$?"
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))

  echo
  echo "== Packer image build summary =="
  if [[ "$exit_code" -eq 0 ]]; then
    echo "Status: success"
  else
    echo "Status: failure (exit code: $exit_code)"
  fi
  echo "Total duration: $(format_duration "$elapsed_seconds")"
  echo "Log file: $LOG_FILE"
}

trap print_execution_summary EXIT

echo "LOG_FILE=$LOG_FILE"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Missing credentials file: $CREDENTIALS_FILE" >&2
  exit 1
fi

for command_name in aws jq packer; do
  command -v "$command_name" >/dev/null || {
    echo "Required command not found: $command_name" >&2
    exit 1
  }
done

# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

if [[ -f "$VENV_DIR/bin/activate" ]]; then
  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"
fi
command -v ansible-playbook >/dev/null || {
  echo "ansible-playbook not found; activate/install the TP Ansible environment or set VENV_DIR." >&2
  exit 1
}
ansible-doc -t module community.general.snap >/dev/null 2>&1 || {
  echo "community.general.snap is unavailable in the active Ansible environment." >&2
  exit 1
}

if [[ ! "${TF_VAR_tp_names:-}" ]]; then
  echo "TF_VAR_tp_names must be set to [\"tpiac\"] to build this IaC baseline image." >&2
  exit 1
fi
if ! jq -e 'type == "array" and length == 1 and .[0] == "tpiac"' <<<"$TF_VAR_tp_names" >/dev/null; then
  echo "This POC builds the pinned IaC-only student image; set TF_VAR_tp_names='[\"tpiac\"]'." >&2
  exit 1
fi

export PKR_VAR_aws_region="${TPCS_PACKER_BUILD_REGION:-${AWS_DEFAULT_REGION:-eu-west-3}}"
export PKR_VAR_source_ami="${TPCS_PACKER_SOURCE_AMI:-ami-01d21b7be69801c2f}"
export PKR_VAR_build_instance_type="${TPCS_PACKER_BUILD_INSTANCE_TYPE:-m5.large}"
export PKR_VAR_subnet_id="${TPCS_PACKER_SUBNET_ID:-}"
export PKR_VAR_ami_name_prefix="${TPCS_PACKER_AMI_NAME_PREFIX:-tpcs-student-jammy}"

if [[ "$PKR_VAR_aws_region" != "eu-west-3" ]]; then
  echo "The Terraform platform currently runs in eu-west-3; build the AMI in eu-west-3." >&2
  exit 1
fi

aws_account_id="$(aws sts get-caller-identity --query Account --output text --no-cli-pager)"
expected_account_id="${TPCS_EXPECTED_AWS_ACCOUNT_ID:-${TF_VAR_tpcs_aws_account_id:-}}"
if [[ -n "$expected_account_id" && "$aws_account_id" != "$expected_account_id" ]]; then
  echo "AWS credentials resolve to account $aws_account_id, expected $expected_account_id; stopping." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/terraform-infra/.tpcs"
cd "$PACKER_DIR"
packer init .
packer validate .

echo "AWS account: $aws_account_id"
echo "Build region: $PKR_VAR_aws_region"
echo "Source AMI: $PKR_VAR_source_ami"
echo "Build instance type: $PKR_VAR_build_instance_type"
echo "The build launches a temporary EC2 instance and creates a billable AMI/snapshot."
if [[ "$AUTO_APPROVE" != true ]]; then
  read -r -p "Continue with the Packer build? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Build cancelled."; exit 0; }
fi

packer build .

manifest="$ROOT_DIR/terraform-infra/.tpcs/packer-student-manifest.json"
ami_id="$(jq -er '.builds[-1].artifact_id | split(":")[-1] | select(test("^ami-[0-9a-f]+$"))' "$manifest")"
tfvars_tmp="$ROOT_DIR/terraform-infra/packer-student.auto.tfvars.json.tmp"
jq -n --arg student_ami_packer_id "$ami_id" '{student_ami_packer_id: $student_ami_packer_id}' > "$tfvars_tmp"
chmod 600 "$tfvars_tmp"
mv "$tfvars_tmp" "$ROOT_DIR/terraform-infra/packer-student.auto.tfvars.json"

echo "Student AMI created: $ami_id"
echo "Terraform variable file: $ROOT_DIR/terraform-infra/packer-student.auto.tfvars.json"
echo "Set TF_VAR_student_ami_source=packer in credentials-setup.sh to select it on a later apply."
