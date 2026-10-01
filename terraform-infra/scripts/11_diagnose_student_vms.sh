#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform-infra"
source "$ROOT_DIR/scripts/tpcs-credentials.sh"
tpcs_load_credentials "${CREDENTIALS_FILE:-$TF_DIR/credentials-setup.sh}"
SSH_KEY="${TF_DIR}/key"
DNS_SUBDOMAIN="${TF_VAR_dns_subdomain:-tpcsonline.org}"

if [[ ! -r "${SSH_KEY}" ]]; then
  echo "SSH key not readable: ${SSH_KEY}" >&2
  exit 1
fi

if [[ "$#" -gt 0 ]]; then
  VMS=("$@")
else
  mapfile -t VMS < <(
    "$ROOT_DIR/tf.sh" output -json student_vm |
      jq -r '.[0].dns[]? | split(".")[0]' 2>/dev/null
  )
fi

if [[ "${#VMS[@]}" -eq 0 ]]; then
  echo "Usage: $0 vm02 [vm04 ...]" >&2
  echo "Or run from an initialized Terraform workspace with student_vm output." >&2
  exit 1
fi

for vm in "${VMS[@]}"; do
  host="${vm}.${DNS_SUBDOMAIN}"
  echo
  echo "===== ${host} ====="
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -i "${SSH_KEY}" "${vm}@${host}" 'bash -s' <<'REMOTE'
set -u

token="$(curl -fsS -m 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)"
meta() {
  curl -fsS -m 2 -H "X-aws-ec2-metadata-token: ${token}" "http://169.254.169.254/latest/meta-data/$1" 2>/dev/null || true
}
sum_rss_mb() {
  ps -eo comm,rss 2>/dev/null | awk -v pattern="$1" '$1 ~ pattern {s+=$2} END{printf "%.0f", s/1024}'
}

echo "host=$(hostname)"
echo "instance_type=$(meta instance-type) instance_id=$(meta instance-id) az=$(meta placement/availability-zone)"
awk '/MemTotal|MemAvailable|SwapTotal|SwapFree/ {printf "%s=%s_kB ", $1, $2} END{print ""}' /proc/meminfo
free -h
swapon --show || true
df -h / /home 2>/dev/null || true

echo "rss_summary_mb code=$(sum_rss_mb '^code$') chrome=$(sum_rss_mb '^chrome$') terraform_related=$(sum_rss_mb 'terraform|terraform-ls|ansible') docker_related=$(sum_rss_mb 'dockerd|containerd')"

echo "recent_reboots"
last -x reboot shutdown 2>/dev/null | head -12 || true

echo "top_rss"
ps -eo pid,ppid,user,stat,%cpu,%mem,rss,comm,args --sort=-rss | head -20 || true

echo "oom_hung_watchdog_logs"
for boot in -5 -4 -3 -2 -1 0; do
  sudo journalctl -b "${boot}" -k --no-pager 2>/dev/null |
    grep -Ei 'out of memory|oom|killed process|blocked for more than|hung task|watchdog|soft lockup|segfault' |
    tail -20 |
    sed "s/^/boot ${boot}: /" || true
done

echo "systemd_oomd"
sudo journalctl --since '2 days ago' -u systemd-oomd --no-pager 2>/dev/null | tail -60 || true
REMOTE
done
