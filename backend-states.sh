#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  exec python3 "$ROOT_DIR/scripts/tpcs_states.py" "$@"
fi
source "${CREDENTIALS_FILE:-$ROOT_DIR/terraform-infra/credentials-setup.sh}"
exec python3 "$ROOT_DIR/scripts/tpcs_states.py" "$@"
