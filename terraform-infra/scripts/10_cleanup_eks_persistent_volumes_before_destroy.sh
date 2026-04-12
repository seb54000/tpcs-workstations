#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/.."
FORCE_ORPHAN_DELETE="${FORCE_ORPHAN_DELETE:-true}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }
}

need_cmd terraform
need_cmd jq
need_cmd aws

if [[ ! -d "$TF_DIR" ]]; then
  echo "Terraform directory not found: $TF_DIR"
  exit 1
fi

if [[ -n "${TF_OUTPUT_JSON_CACHE:-}" ]]; then
  TF_OUTPUT_JSON="$TF_OUTPUT_JSON_CACHE"
else
  pushd "$TF_DIR" >/dev/null
  TF_OUTPUT_JSON="$(terraform output -json)"
  popd >/dev/null
fi

CLUSTER_ENTRIES="$(echo "$TF_OUTPUT_JSON" | jq -rc '.eks_clusters.value // {} | to_entries[]?')"
if [[ -z "$CLUSTER_ENTRIES" ]]; then
  echo "No EKS clusters in terraform output. Nothing to clean."
  exit 0
fi

find_cluster_csi_volumes() {
  local region="$1"
  local cluster_name="$2"

  aws ec2 describe-volumes --region "$region" --output json \
    | jq -rc --arg cn "$cluster_name" '
        .Volumes[]
        | select(
            any(.Tags[]?; .Key == ("kubernetes.io/cluster/" + $cn) and (.Value == "owned" or .Value == "shared"))
            and any(.Tags[]?;
              .Key == "ebs.csi.aws.com/cluster"
              or .Key == "CSIVolumeName"
              or (.Key | startswith("kubernetes.io/created-for/"))
            )
          )
      '
}

delete_volume_if_possible() {
  local region="$1"
  local volume_id="$2"
  local state="$3"

  if [[ "$state" == "available" ]]; then
    echo "    deleting available volume: $volume_id"
    aws ec2 delete-volume --region "$region" --volume-id "$volume_id"
    return
  fi

  if [[ "$FORCE_ORPHAN_DELETE" != "true" ]]; then
    echo "    skipping attached volume (set FORCE_ORPHAN_DELETE=true to force detach/delete): $volume_id"
    return
  fi

  echo "    force-detaching attached volume: $volume_id"
  aws ec2 detach-volume --region "$region" --volume-id "$volume_id" --force >/dev/null || true
  echo "    waiting volume available: $volume_id"
  aws ec2 wait volume-available --region "$region" --volume-ids "$volume_id"
  echo "    deleting detached volume: $volume_id"
  aws ec2 delete-volume --region "$region" --volume-id "$volume_id"
}

echo "Cleaning up EBS volumes created by EKS PVC/CSI..."
while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  cluster_name="$(echo "$entry" | jq -r '.value.cluster_name')"
  region="$(echo "$entry" | jq -r '.value.region')"
  echo
  echo "- cluster $cluster_name ($region)"

  volumes_json="$(find_cluster_csi_volumes "$region" "$cluster_name")"
  if [[ -z "$volumes_json" ]]; then
    echo "  no EBS CSI/PV volume matched cluster tags"
    continue
  fi

  while IFS= read -r volume; do
    [[ -z "$volume" ]] && continue
    volume_id="$(echo "$volume" | jq -r '.VolumeId')"
    state="$(echo "$volume" | jq -r '.State')"
    az="$(echo "$volume" | jq -r '.AvailabilityZone')"
    attachment_count="$(echo "$volume" | jq '[.Attachments[]?] | length')"
    echo "  - $volume_id state=$state az=$az attachments=$attachment_count"
    delete_volume_if_possible "$region" "$volume_id" "$state"
  done <<< "$volumes_json"
done <<< "$CLUSTER_ENTRIES"

echo
echo "EBS PVC/CSI cleanup done."
echo "This helper only targets volumes tagged both for the EKS cluster and for CSI/PV provisioning."
