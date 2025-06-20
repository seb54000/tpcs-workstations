#!/bin/bash

OUTPUT_FILE="/var/www/html/json/aws_ec2_metrics.prom"
TMP_FILE=$(mktemp)

echo "# HELP aws_instance Number of running EC2 instances" > "$TMP_FILE"
echo "# TYPE aws_instance gauge" >> "$TMP_FILE"

for REGION in eu-central-1 eu-west-1 eu-west-2 eu-west-3 eu-south-1 eu-south-2 eu-north-1 eu-central-2; do
  # Récupérer les instances de la région
  INSTANCES=$(aws ec2 describe-instances --region "$REGION" --output json)

    echo "$INSTANCES" | jq -r '
    .Reservations[].Instances[] as $i |
    ($i.Tags // [])
        | map(select(.Key=="Name"))
        | .[0].Value // "unknown"
        | {
            name: .,
            state: $i.State.Name,
            flavor: $i.InstanceType,
            region: "'$REGION'"
        }
        | "aws_instance{user=\"" + .name + "\", flavor=\"" + .flavor + "\", state=\"" + .state + "\", region=\"" + .region + "\"} 1"
    ' >> "$TMP_FILE"

    # VPCs
    aws ec2 describe-vpcs --region "$REGION" --output json | jq -r --arg region "$REGION" '
    .Vpcs[] |
    "aws_vpc{region=\"" + $region + "\", vpc_id=\"" + .VpcId + "\", cidr=\"" + .CidrBlock + "\"} 1"
    ' >> "$TMP_FILE"

    # Internet Gateways
    aws ec2 describe-internet-gateways --region "$REGION" --output json | jq -r --arg region "$REGION" '
    .InternetGateways[] |
    "aws_internet_gateway{region=\"" + $region + "\", igw_id=\"" + .InternetGatewayId + "\"} 1"
    ' >> "$TMP_FILE"

    # Security Groups
    aws ec2 describe-security-groups --region "$REGION" --output json | jq -r --arg region "$REGION" '
    .SecurityGroups[] |
    "aws_security_group{region=\"" + $region + "\", sg_id=\"" + .GroupId + "\", name=\"" + .GroupName + "\"} 1"
    ' >> "$TMP_FILE"

    # EIPs
    aws ec2 describe-addresses --region "$REGION" --output json | jq -r --arg region "$REGION" '
    .Addresses[] |
    "aws_eip{region=\"" + $region + "\", public_ip=\"" + .PublicIp + "\", allocation_id=\"" + (.AllocationId // "none") + "\"} 1"
    ' >> "$TMP_FILE"
done

sudo mv "$TMP_FILE" "$OUTPUT_FILE"
sudo chmod 644 "$OUTPUT_FILE"