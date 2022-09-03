### Settings for deployment

export AWS_ACCESS_KEY_ID=*************
export AWS_SECRET_ACCESS_KEY=***************
export AWS_DEFAULT_REGION=us-east-1

export TF_VAR_ec2_user_passwd="**********"
export TF_VAR_cloudus_user_passwd="****************"
export TF_VAR_vm_dns_record_suffix=**************


### use terraform

`terraform plan`

Change number of deisred VMs

```
export TF_VAR_vm_number=3

# or

terraform apply -var="vm_number=3"
```