#!/usr/bin/env bash
# Shared validation before preparing or destroying a platform.
tpcs_validate_tp_names() {
  if ! jq -e -s '
    length == 1 and (.[0] |
      if type == "array" then
        length > 0 and all(.[]; . == "tpiac" or . == "tpkube" or . == "tpmon")
      else false end)
  ' <<< "${TF_VAR_tp_names:-}" >/dev/null; then
    echo 'Invalid TF_VAR_tp_names. Set a non-empty JSON array containing only tpiac, tpkube or tpmon.' >&2
    return 1
  fi
}
