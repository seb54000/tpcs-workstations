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
need_cmd kubectl

if [[ ! -d "$TF_DIR" ]]; then
  echo "Terraform directory not found: $TF_DIR"
  exit 1
fi

pushd "$TF_DIR" >/dev/null
TF_OUTPUT_JSON="$(terraform output -json)"
popd >/dev/null

CLUSTER_ENTRIES="$(echo "$TF_OUTPUT_JSON" | jq -rc '.eks_clusters.value // {} | to_entries[]?')"
if [[ -z "$CLUSTER_ENTRIES" ]]; then
  echo "No EKS clusters in terraform output. Nothing to clean."
  exit 0
fi

TMP_KUBECONFIG="$(mktemp)"
trap 'rm -f "$TMP_KUBECONFIG"' EXIT

echo "Preparing temporary kubeconfig for all EKS clusters..."
while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  alias_name="$(echo "$entry" | jq -r '.key')"
  cluster_name="$(echo "$entry" | jq -r '.value.cluster_name')"
  region="$(echo "$entry" | jq -r '.value.region')"
  echo "- $alias_name ($cluster_name / $region)"
  aws eks update-kubeconfig \
    --kubeconfig "$TMP_KUBECONFIG" \
    --name "$cluster_name" \
    --region "$region" \
    --alias "$alias_name" >/dev/null
done <<< "$CLUSTER_ENTRIES"

delete_lb_services_for_context() {
  local ctx="$1"
  local svc_lines
  svc_lines="$(kubectl --kubeconfig "$TMP_KUBECONFIG" --context "$ctx" get svc -A -o json \
    | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"')"
  if [[ -z "$svc_lines" ]]; then
    echo "  [$ctx] no Service type=LoadBalancer"
    return
  fi
  echo "  [$ctx] deleting Service type=LoadBalancer:"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ns="$(awk '{print $1}' <<< "$line")"
    name="$(awk '{print $2}' <<< "$line")"
    echo "    - ${ns}/${name}"
    kubectl --kubeconfig "$TMP_KUBECONFIG" --context "$ctx" -n "$ns" delete svc "$name" --ignore-not-found
  done <<< "$svc_lines"
}

wait_no_lb_services_for_context() {
  local ctx="$1"
  local max_attempts=36
  local sleep_seconds=10
  local remaining
  for ((i=1; i<=max_attempts; i++)); do
    remaining="$(kubectl --kubeconfig "$TMP_KUBECONFIG" --context "$ctx" get svc -A -o json \
      | jq '[.items[] | select(.spec.type=="LoadBalancer")] | length')"
    if [[ "$remaining" == "0" ]]; then
      echo "  [$ctx] all LB services removed."
      return
    fi
    echo "  [$ctx] waiting LB services deletion ($remaining remaining) - attempt $i/$max_attempts"
    sleep "$sleep_seconds"
  done
  echo "  [$ctx] timeout waiting for LB services deletion."
  return 1
}

echo
echo "Deleting Kubernetes LoadBalancer services..."
while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  alias_name="$(echo "$entry" | jq -r '.key')"
  delete_lb_services_for_context "$alias_name"
done <<< "$CLUSTER_ENTRIES"

echo
echo "Waiting for service cleanup propagation..."
while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  alias_name="$(echo "$entry" | jq -r '.key')"
  wait_no_lb_services_for_context "$alias_name" || true
done <<< "$CLUSTER_ENTRIES"

if [[ "$FORCE_ORPHAN_DELETE" == "true" ]]; then
  echo
  echo "FORCE_ORPHAN_DELETE=true: deleting orphan ALB/NLB tagged by cluster..."
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    cluster_name="$(echo "$entry" | jq -r '.value.cluster_name')"
    region="$(echo "$entry" | jq -r '.value.region')"
    echo "- cluster $cluster_name ($region)"

    lb_arns="$(aws elbv2 describe-load-balancers --region "$region" --query 'LoadBalancers[].LoadBalancerArn' --output text || true)"
    for lb_arn in $lb_arns; do
      tags_json="$(aws elbv2 describe-tags --region "$region" --resource-arns "$lb_arn" --output json)"
      if echo "$tags_json" | jq -e --arg cn "$cluster_name" '
          .TagDescriptions[].Tags
          | any((.Key=="kubernetes.io/cluster/"+$cn and (.Value=="owned" or .Value=="shared")) or (.Key=="elbv2.k8s.aws/cluster" and .Value==$cn))
        ' >/dev/null; then
        echo "  deleting orphan LB: $lb_arn"
        aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$lb_arn"
      fi
    done
  done <<< "$CLUSTER_ENTRIES"
fi

echo
echo "Cleanup done. You can now run:"
echo "  cd terraform-infra && terraform destroy"
echo
echo "If a subnet is still blocked, check AWS Console:"
echo "- EC2 > Load Balancers (filter tags: kubernetes.io/cluster/<cluster_name>)"
echo "- EC2 > Target Groups linked to these load balancers"
