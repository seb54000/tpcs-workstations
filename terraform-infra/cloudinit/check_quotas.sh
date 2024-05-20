#! /bin/bash

for region in eu-west-1 eu-west-2 eu-west-3 eu-north-1 eu-central-1 eu-central-2 eu-south-1 eu-south-2
do
    echo "$region"
    # for component in ec2_eip_count elb_alb_count elb_clb_count elb_listeners_per_alb elb_listeners_per_clb elb_listeners_per_nlb elb_nlb_count elb_target_group_count elb_target_groups_per_alb
    for component in ec2_on_demand_standard_count ec2_eip_count elb_alb_count elb_clb_count elb_nlb_count iam_group_count iam_user_count s3_bucket_count vpc_count vpc_subnets_per_vpc 
    do
        sudo docker run -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${region} ghcr.io/brennerm/aws-quota-checker check ${component} | grep -v Collecting | grep -v 'AWS profile'
    done

done