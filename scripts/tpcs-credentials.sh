#!/usr/bin/env bash
# Load portable credentials and materialize the TP VM key without exporting it.

_TPCS_CREDENTIALS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TPCS_CREDENTIALS_ROOT="$(cd "$_TPCS_CREDENTIALS_LIB_DIR/.." && pwd)"

tpcs_restore_ssh_key() {
  local private_key_b64="${TPCS_SSH_PRIVATE_KEY_B64:-}"
  unset TPCS_SSH_PRIVATE_KEY_B64
  local status=0
  python3 "$_TPCS_CREDENTIALS_LIB_DIR/tpcs_ssh_key.py" \
    "$_TPCS_CREDENTIALS_ROOT/terraform-infra" \
    <<< "$private_key_b64" || status=$?
  private_key_b64=''
  return "$status"
}

tpcs_select_aws_account() {
  local account="${1:-${TPCS_AWS_ACCOUNT:-}}"
  account="${account^^}"
  case "$account" in
    ECOLE|PERSO) ;;
    *)
      echo "TPCS_AWS_ACCOUNT must be ECOLE or PERSO (got '${account:-unset}')." >&2
      return 1
      ;;
  esac

  local access_key_name="TPCS_AWS_ACCESS_KEY_ID_${account}"
  local secret_key_name="TPCS_AWS_SECRET_ACCESS_KEY_${account}"
  local account_id_name="TPCS_AWS_ACCOUNT_ID_${account}"
  local access_key="${!access_key_name:-}"
  local secret_key="${!secret_key_name:-}"
  local account_id="${!account_id_name:-}"

  # Accept a legacy single-account credentials file while users migrate it.
  if [[ -z "$access_key" || -z "$secret_key" ]]; then
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" \
      && ( -z "${TPCS_AWS_ACCOUNT:-}" || "${TPCS_AWS_ACCOUNT^^}" == "$account" ) ]]; then
      access_key="$AWS_ACCESS_KEY_ID"
      secret_key="$AWS_SECRET_ACCESS_KEY"
    else
      echo "Missing credentials for AWS account alias $account in $TPCS_CREDENTIALS_FILE_ACTIVE." >&2
      return 1
    fi
  fi

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
  export AWS_ACCESS_KEY_ID="$access_key"
  export AWS_SECRET_ACCESS_KEY="$secret_key"
  if [[ -n "$account_id" ]]; then
    export TPCS_EXPECTED_AWS_ACCOUNT_ID="$account_id"
  else
    unset TPCS_EXPECTED_AWS_ACCOUNT_ID
  fi
  export TPCS_AWS_ACCOUNT_ACTIVE="$account"
}

tpcs_source_credentials() {
  local credentials_file="$1"
  if [[ ! -f "$credentials_file" ]]; then
    echo "Missing credentials file: $credentials_file" >&2
    return 1
  fi
  local account_override="${2:-}"
  TPCS_CREDENTIALS_FILE_ACTIVE="$credentials_file"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
  unset TPCS_EXPECTED_AWS_ACCOUNT_ID TPCS_AWS_ACCOUNT_ACTIVE
  unset TF_VAR_student_ami_source TF_VAR_student_ami_packer_id TF_VAR_student_ami_packer_account_id
  # shellcheck source=/dev/null
  source "$credentials_file" || return
  tpcs_select_aws_account "${account_override:-${TPCS_AWS_ACCOUNT:-}}"
}

tpcs_load_credentials() {
  tpcs_source_credentials "$@" || return
  tpcs_restore_ssh_key
}
