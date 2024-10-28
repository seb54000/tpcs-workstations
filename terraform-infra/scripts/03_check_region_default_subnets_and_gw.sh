#!/bin/bash

source $(dirname "$0")/../credentials-setup.sh

for region in eu-central-1 eu-west-1 eu-west-2 eu-west-3 eu-south-1 eu-south-2 eu-north-1 eu-central-2
do
    echo "============"
    echo "${region}"
    DEFAULT_VPC_ID=$(aws --region ${region} ec2 describe-vpcs | jq -r '.[] | .[] | select (.IsDefault==true) .VpcId')
    # Check that var is not empty and begin with vpc-
    if [[ "$DEFAULT_VPC_ID" == vpc-* ]]; then
        echo -e "\e[32mdefault VPC ID for region ${region} : $DEFAULT_VPC_ID\e[0m"
    else
        echo -e "\e[31mError no default VPC for region ${region}\e[0m"
        echo "You should consider creating one with :"
        echo "aws --region ${region} ec2 create-default-vpc"
        break
    fi

    DEFAULT_SUBNET_ID=$(aws --region ${region} ec2 describe-subnets | jq '.[] | .[] | select(.DefaultForAz==true) .SubnetId')
    DEFAULT_SUBNET_ID_COUNT=$(echo "$DEFAULT_SUBNET_ID" | wc -l)
    if [ "$DEFAULT_SUBNET_ID_COUNT" -eq 3 ]; then
        echo -e "\e[32mOK 3 subnets for region ${region}\e[0m"
    else
        echo -e "\e[31mKO default subnets number for region ${region} is $DEFAULT_SUBNET_ID_COUNT\e[0m"
        echo "You should consider creating missing default subnets"
        echo "Here are the details of existing default subnets"
        echo "$DEFAULT_SUBNET_ID"
        echo "You can use following commands to complete the missing default subnets"
        echo "aws ec2 --region ${region} create-default-subnet --availability-zone ${region}a"
        echo "aws ec2 --region ${region} create-default-subnet --availability-zone ${region}b"
        echo "aws ec2 --region ${region} create-default-subnet --availability-zone ${region}c"
        break
    fi

    # Check if an INTERNET gateway is correctly associated with VPC (otherwise, access to ressources wil be impossible, eg. SSH)
    INTERNET_GW_ATTACHEMENT=$(aws --region ${region} ec2 describe-internet-gateways | jq ".[] | .[].Attachments[] | select (.VpcId==\"${DEFAULT_VPC_ID}\") | length")
    if [ -n "$INTERNET_GW_ATTACHEMENT" ]; then
    echo -e "\e[32mOK there is an internet gateway attached to the default VPC $DEFAULT_VPC_ID\e[0m"
    else
        echo -e "\e[31mno INTERNET GW is attached to default VPC (SSH won't work)\e[0m"
        echo "Region : ${region} : Go to console and check if one INT GW is available"
        echo "if not, create a new one and attached it to default vpc : https://docs.aws.amazon.com/cli/latest/reference/ec2/attach-internet-gateway.html"
    fi
  echo ""
done

