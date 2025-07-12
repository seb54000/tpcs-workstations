#!/bin/bash

ssh_quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
source $(dirname "$0")/../credentials-setup.sh

# Find all tfstate files in the VM to be sure there was no terraform test outside our framework
for ((i=0; i<$TF_VAR_vm_number; i++))
do
    digits=$(printf "%02d" $i)
    # echo "Looking for tfstate files in vm${digits}"
    ${ssh_quiet} -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org "sudo find / -name "terraform.tfstate" -size +200c -exec ls -lh {} ';' 2> /dev/null" &
done
wait

# echo "Next step destroy"
# # If state file are 180-182 bytes, it means they are empty and destroy already has been done
# # If there is somethinkg there are usually some Kbytes

REMOTE_COMMAND=$(cat <<'EOF'
# Find all terraform.tfstate files
sudo find / -type f -name "terraform.tfstate" -size +200c 2>/dev/null | while read tfstate; do
    dir=$(dirname "$tfstate")
    echo "Found state file in $dir"
    cd "$dir" || continue
    echo "Running terraform destroy (with auto-approve) in $dir"
    terraform destroy -auto-approve
done
EOF
)

# for ((i=0; i<$TF_VAR_vm_number; i++))
# do
#     echo "Processing vm${digits}"
#     ${ssh_quiet} -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org "$REMOTE_COMMAND" &
# done
# wait

# echo "Job completely finished including destroy"


