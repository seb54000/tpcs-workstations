# Source this library after loading credentials. Nothing runs on source.
tpcs_backend_select() {
  local settings
  settings=$(python3 "$ROOT_DIR/scripts/tpcs_backend.py" env) || return
  # Only shell-quoted non-secret configuration is emitted by the Python helper.
  eval "$settings"
  export TPCS_EXPECTED_AWS_ACCOUNT_ID="$TPCS_AWS_ACCOUNT_ID"
}

tpcs_terraform() {
  python3 "$ROOT_DIR/scripts/tpcs_backend.py" "$@"
}
