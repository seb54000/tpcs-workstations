#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_START_SECONDS=$SECONDS
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$HOME/ansiblevenv}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$ROOT_DIR/terraform-infra/credentials-setup.sh}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
COLOR_LOG="${COLOR_LOG:-/tmp/tpcs-workstations-tpmon-${RUN_ID}.ansi.log}"
PLAIN_LOG="${PLAIN_LOG:-/tmp/tpcs-workstations-tpmon-${RUN_ID}.log}"
MODE="${1:-run}"

print_usage() {
  cat <<EOF
Usage:
  $(basename "$0") [run|cleanup|help]

Modes:
  run      Run the complete TP monitoring validation, then clean it up (default).
  cleanup  Stop load tests and delete the three generated Kubernetes manifests.
  help     Show this help.

Prerequisites (run manually before this script):
  source "$VENV_DIR/bin/activate"
  cd "$ROOT_DIR"

Credentials are loaded automatically from:
  $CREDENTIALS_FILE

The script must use the Ansible configuration from:
  $ROOT_DIR/ansible.cfg

Environment overrides:
  VENV_DIR   Expected Ansible virtual environment (default: $HOME/ansiblevenv)
  CREDENTIALS_FILE  Credentials path (default: terraform-infra/credentials-setup.sh)
  COLOR_LOG  ANSI/color log path (default: /tmp/tpcs-workstations-tpmon-<date>.ansi.log)
  PLAIN_LOG  Log path without ANSI codes (default: /tmp/tpcs-workstations-tpmon-<date>.log)

Colored logs can be read with: less -R <file>
EOF
}

case "$MODE" in
  run|cleanup)
    ;;
  help|-h|--help)
    print_usage
    exit 0
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    print_usage >&2
    exit 2
    ;;
esac

if [[ ! -f "$ROOT_DIR/ansible.cfg" ]]; then
  echo "Missing Ansible configuration: $ROOT_DIR/ansible.cfg" >&2
  exit 1
fi

if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
  echo "Missing Ansible virtual environment: $VENV_DIR/bin/activate" >&2
  echo "See the prerequisites with: $(basename "$0") help" >&2
  exit 1
fi

if [[ "${VIRTUAL_ENV:-}" != "$VENV_DIR" ]]; then
  echo "The expected Ansible virtual environment is not active." >&2
  echo "Run: source \"$VENV_DIR/bin/activate\"" >&2
  exit 1
fi

source "$ROOT_DIR/scripts/tpcs-credentials.sh"
tpcs_load_credentials "$CREDENTIALS_FILE"

if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  echo "AWS credentials are not loaded in the current shell." >&2
  echo "Check: $CREDENTIALS_FILE" >&2
  exit 1
fi

command -v ansible >/dev/null || {
  echo "ansible is not available in PATH after activating $VENV_DIR" >&2
  exit 1
}
command -v perl >/dev/null || {
  echo "perl is required to create the log without ANSI color codes" >&2
  exit 1
}

source "$ROOT_DIR/scripts/tpcs-backend.sh"
tpcs_backend_select

mkdir -p "$(dirname "$COLOR_LOG")" "$(dirname "$PLAIN_LOG")"
: >"$COLOR_LOG"
: >"$PLAIN_LOG"

# Keep one byte-for-byte ANSI log and continuously strip terminal escape
# sequences into a second log. tee's stdout remains connected to the terminal.
exec > >(
  tee -a "$COLOR_LOG" >(
    perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g' >>"$PLAIN_LOG"
  )
) 2>&1

export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-true}"
export PY_COLORS="${PY_COLORS:-1}"
export CLICOLOR="${CLICOLOR:-1}"
export CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}"

cd "$ROOT_DIR"

format_duration() {
  local total_seconds="$1"
  printf '%02dh %02dm %02ds' \
    "$((total_seconds / 3600))" \
    "$(((total_seconds % 3600) / 60))" \
    "$((total_seconds % 60))"
}

print_summary() {
  local exit_code=$?
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))

  echo
  echo "== Execution summary =="
  if ((exit_code == 0)); then
    echo "Status: success"
  else
    echo "Status: failure (exit code: $exit_code)"
    echo "The script stopped at the first failed validation step."
    echo "To remove a partial deployment: $(basename "$0") cleanup"
  fi
  echo "Total duration: $(format_duration "$elapsed_seconds")"
  echo "Color log: $COLOR_LOG"
  echo "Plain log: $PLAIN_LOG"
}

trap print_summary EXIT

run_step() {
  local title="$1"
  shift

  echo
  echo "========================================================================"
  echo "== $title"
  echo "== Started at $(date --iso-8601=seconds)"
  echo "========================================================================"
  time "$@"
}

pause_between_steps() {
  echo
  echo "Waiting 5 seconds before the next step..."
  sleep 5
}

stop_load_tests() {
  run_step "Stop all load tests" \
    ansible role_student \
      -m ansible.builtin.shell \
      -a 'for f in ~/.tpcs-tools/load-test*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null || true; rm -f "$f"; done; pkill -f "[p]ython3 load_test.py" 2>/dev/null || true' \
      -f 10
}

delete_manifests() {
  run_step "Delete TP monitoring Kubernetes manifests" \
    ansible role_student \
      -m ansible.builtin.shell \
      -a 'set -e; VM="$(id -un)"; CTX="${CTX:-cluster00}"; ADMIN_CTX="${CTX}-admin"; CLUSTER_NUM="${CTX#cluster}"; WORKDIR="$HOME/.tpcs-tools/eks-demoboard-monitoring"; for manifest in "$WORKDIR/demoboard-v2.${VM}.eks${CLUSTER_NUM}.yaml" "$WORKDIR/demoboard-v1.${VM}.eks${CLUSTER_NUM}.yaml" "$WORKDIR/monitoring-lgtm.${VM}.eks${CLUSTER_NUM}.yaml"; do if [ -f "$manifest" ]; then echo "Deleting $manifest"; kubectl --kubeconfig "$HOME/.kube/config.eks.admin" --context "$ADMIN_CTX" delete --ignore-not-found=true -f "$manifest"; else echo "Manifest not found, skipping: $manifest"; fi; done' \
      -f 3 \
      -B 1800 \
      -P 15
}

echo "== tpcs-workstations - global TP monitoring validation =="
echo "Mode: $MODE"
echo "Ansible directory: $ROOT_DIR"
echo "Ansible venv: $VIRTUAL_ENV"
echo "Ansible config: $ROOT_DIR/ansible.cfg"
echo "Credentials: loaded (values are not displayed)"
echo "Color log: $COLOR_LOG"
echo "Plain log: $PLAIN_LOG"

if [[ "$MODE" == "cleanup" ]]; then
  stop_load_tests
  pause_between_steps
  delete_manifests
  exit 0
fi

run_step "Check hostnames on all student VMs" \
  ansible role_student \
    -m ansible.builtin.shell \
    -a 'hostname'

pause_between_steps

run_step "Run the complete TP monitoring build and deployment scenario" \
  ansible role_student \
    -m ansible.builtin.shell \
    -a 'CTX=cluster00 bash ~/tpmon_eks_demoboard_monitoring_lgtm.sh' \
    -f 3 \
    -B 7200 \
    -P 30

pause_between_steps

run_step "Start the standard load test" \
  ansible role_student \
    -m ansible.builtin.shell \
    -a 'VM="$(id -un)"; cd ~/tp-cs-monitoring-student/03-demoboard; nohup python3 load_test.py "https://demoboard-${VM}.eks00.seb.tpcsonline.org/api" > ~/.tpcs-tools/load-test.log 2>&1 & echo $! > ~/.tpcs-tools/load-test.pid' \
    -f 10

pause_between_steps

run_step "Deploy Demoboard mode 2 and wait for its rollouts" \
  ansible role_student \
    -m ansible.builtin.shell \
    -a 'set -e; VM="$(id -un)"; CTX="${CTX:-cluster00}"; ADMIN_CTX="${CTX}-admin"; MANIFEST="$HOME/.tpcs-tools/eks-demoboard-monitoring/demoboard-v2.${VM}.eks00.yaml"; kubectl --kubeconfig "$HOME/.kube/config.eks.admin" --context "$ADMIN_CTX" apply -f "$MANIFEST"; for d in demoboard-api demoboard-worker demoboard-frontend; do kubectl --kubeconfig "$HOME/.kube/config.eks.admin" --context "$ADMIN_CTX" -n "$VM" rollout status "deploy/$d" --timeout=600s; done' \
    -f 3 \
    -B 1800 \
    -P 15

pause_between_steps

run_step "Start the burst load test" \
  ansible role_student \
    -m ansible.builtin.shell \
    -a 'VM="$(id -un)"; cd ~/tp-cs-monitoring-student/03-demoboard; nohup python3 load_test.py --burst "https://demoboard-${VM}.eks00.seb.tpcsonline.org/api" > ~/.tpcs-tools/load-test-burst.log 2>&1 & echo $! > ~/.tpcs-tools/load-test-burst.pid' \
    -f 10

echo
echo "Letting the standard and burst load tests run for 60 seconds..."
sleep 60

stop_load_tests
pause_between_steps
delete_manifests

echo
echo "TP monitoring validation and cleanup completed successfully."
