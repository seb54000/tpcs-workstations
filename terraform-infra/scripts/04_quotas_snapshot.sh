#!/bin/bash

source $(dirname "$0")/../credentials-setup.sh

LOGFILE="/var/tmp/aws-quota-checker-$(date +%Y%m%d-%H%M%S)"

echo "Take a snapshot of existing quotas in file : ${LOGFILE}"

for region in eu-central-1 eu-west-1 eu-west-2 eu-west-3 eu-south-1 eu-south-2 eu-north-1 eu-central-2
do
  echo "Working on region : ${region} ---------------------"
  sudo docker run -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${region} ghcr.io/brennerm/aws-quota-checker check all | grep -v 0/ | tee -a $LOGFILE
done
sort $LOGFILE | uniq | tee ${LOGFILE}.uniq

