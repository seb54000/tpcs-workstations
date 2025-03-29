#!/bin/bash

# alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
ssh_quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
source $(dirname "$0")/../credentials-setup.sh



for ((i=0; i<1; i++))
do
  digits=$(printf "%02d" $i)
  VM_FQDN="vm${digits}.tpcsonline.org"

  echo "VM : ${VM_FQDN}"
  echo "Connect to 'master' VM to get result of join command (token)"
  JOIN_CMD=$(${ssh_quiet} -o ConnectTimeout=5 -o ConnectionAttempts=1 -i $(dirname "$0")/../key vm${digits}@${VM_FQDN} 'microk8s add-node --format json | jq -r .urls[0]')
  echo ${JOIN_CMD}

  echo "VM : knode${digits}.tpcsonline.org"
  echo "Connect to 'node' VM to launch join command"
  ${ssh_quiet} -o ConnectTimeout=5 -o ConnectionAttempts=1 -i $(dirname "$0")/../key vm${digits}@knode${digits}.tpcsonline.org ''microk8s join ${JOIN_CMD} --worker''

  echo "========================================="

  # TODO what about restart of VMs during night ???

done

