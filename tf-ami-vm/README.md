### Settings for deployment

export AWS_ACCESS_KEY_ID=*************
export AWS_SECRET_ACCESS_KEY=***************
export AWS_DEFAULT_REGION=us-east-1

export TF_VAR_ec2_user_passwd="**********"
export TF_VAR_cloudus_user_passwd="****************"
export TF_VAR_vm_dns_record_suffix=**************
export TF_VAR_iac_user_passwd="**********"

### use terraform

`terraform plan`

Change number of deisred VMs

The tool is used for tp kube (all the tools for docker and kube TP) but also for iac (ansible terraform, only, and simpler init script)

```
export TF_VAR_kube_vm_number=3
export TF_VAR_iac_vm_number=0

# or

terraform apply -var="kube_vm_number=3" -var="iac_vm_number=0"
```

### Connect

http://serverinfo.${TF_VAR_vm_dns_record_suffix}/

ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" -L 33389:localhost:3389 cloudus@vm0.${TF_VAR_vm_dns_record_suffix}


### Debug

ssh -i SSH_KEY ec2-user@vm0.${TF_VAR_vm_dns_record_suffix}

sudo cat /var/log/cloud-init-output.log
sudo tail -f /var/log/cloud-init.log 
sudo cat /var/log/user-data.log



MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4/)

