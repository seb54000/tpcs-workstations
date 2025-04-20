#!/bin/bash

# alias ${ssh_quiet}='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
ssh_quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
source $(dirname "$0")/../credentials-setup.sh

for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  # ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.${TF_VAR_dns_subdomain}" 2&> /dev/null
  ${ssh_quiet} -i $(pwd)/key vm$digits@vm${digits}.${TF_VAR_dns_subdomain} 'cat tpcs-iac/.env | grep REGION'
  export REGION=$(${ssh_quiet} -i $(pwd)/key vm$digits@vm${digits}.${TF_VAR_dns_subdomain} 'cat tpcs-iac/.env | grep REGION' | awk -F= '{ print $NF }' | tr -d '"')
  echo $REGION
  ${ssh_quiet} -i $(pwd)/key vm$digits@vm${digits}.${TF_VAR_dns_subdomain} aws --region ${REGION} ec2 describe-instances | jq -r '.Reservations[].Instances[] | "\(.Tags[] | select(.Key=="Name").Value) \(.State.Name) in \(.Placement.AvailabilityZone)"'
  echo "-----------"
  echo ""
done

