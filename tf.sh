#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -eq 0 || "$1" == help || "$1" == --help || "$1" == -h ]]; then
  exec python3 "$ROOT_DIR/scripts/tpcs_backend.py" --help
fi
# Credentials stay in the operator's private, ignored file (or a supplied path).
source "$ROOT_DIR/scripts/tpcs-credentials.sh"
tpcs_load_credentials "${CREDENTIALS_FILE:-$ROOT_DIR/terraform-infra/credentials-setup.sh}"
exec python3 "$ROOT_DIR/scripts/tpcs_backend.py" "$@"
