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

tpcs_load_credentials() {
  local credentials_file="$1"
  if [[ ! -f "$credentials_file" ]]; then
    echo "Missing credentials file: $credentials_file" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$credentials_file" || return
  tpcs_restore_ssh_key
}
