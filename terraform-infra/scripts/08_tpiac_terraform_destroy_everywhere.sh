#!/bin/bash

ssh_quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
source $(dirname "$0")/../credentials-setup.sh

# rm /var/tmp/tfdestroy-vm*

# for ((i=0; i<$TF_VAR_vm_number; i++))
# do
#   digits=$(printf "%02d" $i)
#   echo "terraform destroy in vm${digits} :"
#   # ${ssh_quiet} -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org "terraform -chdir=/home/vm${digits}/tpcs-iac/terraform/ destroy -auto-approve" | tee -a /var/tmp/tfdestroy-vm${digits}-$(date +%Y%m%d-%H%M%S)
#   # ${ssh_quiet} -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org "source /home/vm${digits}/tpcs-iac/.env && terraform -chdir=/home/vm${digits}/tpcs-iac/vikunja/terraform/ destroy -auto-approve" | tee -a /var/tmp/tfdestroy-vm${digits}-$(date +%Y%m%d-%H%M%S)

#   echo "-----------"
#   echo ""
# done

# grep -e destroyed /var/tmp/tfdestroy-vm*
# grep -e destroyed -e vm /var/tmp/tfdestroy-vm*

# Find all tfstate files in the VM to be sure there was no terraform test outside our framework
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "Looking for tfstate files in vm${digits} :"
  ${ssh_quiet} -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org "sudo find / -name *tfstate* -exec ls -lh {} ';' 2> /dev/null | grep -v backup"
  echo "-----------"
  echo ""
done

# If state file are 180-182 bytes, it means they are empty and destroy already has been done
# If there is somethinkg there are usually some Kbytes