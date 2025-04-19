#!/bin/bash

# alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
ssh_quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
source $(dirname "$0")/../credentials-setup.sh


# docs and access VMs

for i in docs access
do
  VM_FQDN="${i}.tpcsonline.org"
  max_attempts=60
  echo "VM : ${VM_FQDN}"
  for ((j=1; i<=${max_attempts}; j++))
  do
    echo "          Attempt : ${j} / ${max_attempts} -- SSH connection"
    # STATUS=$(ssh -i ~/.ssh/preDEV.maas-user.key -o LogLevel=error -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${VM_FQDN} "sudo cloud-init status")
    STATUS=$(${ssh_quiet} -i $(dirname "$0")/../key -o ConnectTimeout=5 -o ConnectionAttempts=1 access@${VM_FQDN} 'sudo cloud-init status')
    # we need to test the content retruned for cloud init  that should contain done
    # if yes break (otherwise continue)
    if [[ "${STATUS}" == *"done"* ]]
    then
        echo "      ${VM_FQDN} - cloud-init is done !"
        break
    fi
    echo "      ${VM_FQDN} - still waiting (cloud-init status : ${STATUS})"
    sleep 7
    if [ ${j} -eq ${max_attempts} ]
    then
        set -e
        echo "  ${VM_FQDN} - /!\/!\/!\ is definitely unreachable or cloud-init is in error state /!\/!\/!\ "
        exit 1
    fi
    # echo -e "Connected (with SSH) to VM : $(ssh-quiet -i $(pwd)/key vm${vm_number}@${VM_FQDN} 'hostname')"
    # ssh-quiet -i $(dirname "$0")/key vm${vm_number}@${VM_FQDN} 'cat /home/vm${vm_number}/user_data_common_finished 2&> /dev/null && echo "cloudinit finished" || echo "cloudinit still ongoing"'
  done
done



for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  VM_FQDN="vm${digits}.tpcsonline.org"
  max_attempts=60
  echo "VM : ${VM_FQDN}"
  for ((j=1; i<=${max_attempts}; j++))
  do
    echo "          Attempt : ${j} / ${max_attempts} -- SSH connection"
    # STATUS=$(ssh -i ~/.ssh/preDEV.maas-user.key -o LogLevel=error -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${VM_FQDN} "sudo cloud-init status")
    STATUS=$(${ssh_quiet} -i $(dirname "$0")/../key -o ConnectTimeout=5 -o ConnectionAttempts=1 vm${digits}@${VM_FQDN} 'sudo cloud-init status')
    # we need to test the content retruned for cloud init  that should contain done
    # if yes break (otherwise continue)
    if [[ "${STATUS}" == *"done"* ]]
    then
        echo "      ${VM_FQDN} - cloud-init is done !"
        break
    fi
    echo "      ${VM_FQDN} - still waiting (cloud-init status : ${STATUS})"
    sleep 7
    if [ ${j} -eq ${max_attempts} ]
    then
        set -e
        echo "  ${VM_FQDN} - /!\/!\/!\ is definitely unreachable or cloud-init is in error state /!\/!\/!\ "
        exit 1
    fi
    # echo -e "Connected (with SSH) to VM : $(ssh-quiet -i $(pwd)/key vm${vm_number}@${VM_FQDN} 'hostname')"
    # ssh-quiet -i $(dirname "$0")/key vm${vm_number}@${VM_FQDN} 'cat /home/vm${vm_number}/user_data_common_finished 2&> /dev/null && echo "cloudinit finished" || echo "cloudinit still ongoing"'
  done
done

