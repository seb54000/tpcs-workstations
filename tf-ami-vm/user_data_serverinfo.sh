#! /bin/bash -xe
# https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"

sudo yum install -y httpd php
sudo systemctl start httpd
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/)

cat <<EOF > /var/tmp/index.php
<?php
    \$output = shell_exec('aws ec2 describe-instances --region $${AZ::-1} --output text --filters Name=instance-state-name,Values=running --query "Reservations[].Instances[].[InstanceId,PublicIpAddress,Tags[?Key==\'Name\']|[0].Value,Tags[?Key==\'AUTO_DNS_NAME\']|[0].Value]" 2>&1');
    echo "<h1><pre>\$output</pre></h1>";
?>
EOF
sudo mv /var/tmp/index.php /var/www/html/index.php

# Get a DNS record even when IP change at reboot
# https://medium.com/innovation-incubator/how-to-automatically-update-ip-addresses-without-using-elastic-ips-on-amazon-route-53-4593e3e61c4c
sudo curl -o /var/lib/cloud/scripts/per-boot/dns_set_record.sh https://raw.githubusercontent.com/seb54000/tp-centralesupelec/master/tf-ami-vm/dns_set_record.sh
sudo chmod 755 /var/lib/cloud/scripts/per-boot/dns_set_record.sh

echo "### Notify end of user_data ###"
touch /home/ec2-user/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END