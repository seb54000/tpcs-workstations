#! /bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"

## docs related part #############
sudo certbot --nginx -d docs.tpcsonline.org -d www.docs.tpcsonline.org \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'

# Download a list of files (pdf for the TP)
# pip install --upgrade google-api-python-client google-auth-httplib2 google-auth-oauthlib
# python3 /var/tmp/gdrive.py
# rm -f /var/tmp/token.json
# rm -f /var/www/html/index.nginx-debian.html

# Every 5 minutes, run the checks scripts and publish to html file
# echo "*/5 * * * * sudo check_basics > /var/www/html/check_basics.html" | crontab -
wget -O /root/vms.php https://raw.githubusercontent.com/Florian-94/tpcs-workstations/refs/heads/${tpcsws_branch_name}/terraform-infra/cloudinit/vms.php

# Every 5 minutes run the vms.php script to update vms.html summary
echo "*/5 * * * * root php /root/vms.php > /var/tmp/vms.html && mv /var/tmp/vms.html /var/www/html/vms.html" > /etc/cron.d/php_vm_cron

## access (guacamole) related part #############
echo "git clone guacamole docker compose repo"
sudo su - ${username} -c "git clone https://github.com/boschkundendienst/guacamole-docker-compose.git"
# There is a problem with a groupadd 1000 that cause error, we use the working commitID : 92cd822cde165968129c7f2b9ce27f6d91e6b51c
# https://stackoverflow.com/questions/75454944/how-to-clone-a-repository-from-a-specific-commit-id
sudo su - ${username} -c "cd guacamole-docker-compose && git reset --hard 92cd822cde165968129c7f2b9ce27f6d91e6b51c"
sudo su - ${username} -c "cd guacamole-docker-compose && git clean -df"

# Certificate is valid for 90 days, more than enough for our use case - no need to renew
sudo certbot --nginx -d access.tpcsonline.org -d www.access.tpcsonline.org \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'

echo "Now launch the docker compose"
sudo su - ${username} -c "cd guacamole-docker-compose && ./prepare.sh"
sudo su - ${username} -c "cd guacamole-docker-compose && docker-compose up -d"

echo "### install Terraform ###"
wget https://releases.hashicorp.com/terraform/1.6.1/terraform_1.6.1_linux_amd64.zip
unzip terraform_1.6.1_linux_amd64.zip
sudo mv terraform /usr/bin
rm terraform_1.6.1_linux_amd64.zip

# Create guacamole config file with content of var
sudo su - ${username} -c "echo \"${guac_tf_file}\" | base64 -d > guac_config.tf"

sudo su - ${username} -c "terraform init"
sudo su - ${username} -c "terraform apply -auto-approve"

# Deploy Prometheus and Grafana
# Grafana Dashboards links for reference
# https://grafana.com/api/dashboards/11133/revisions/2/download
# https://grafana.com/api/dashboards/1860/revisions/37/download
sudo su - ${username} -c "mkdir -p /var/tmp/grafana/dashboards"
sudo su - ${username} -c "wget -O /var/tmp/grafana/dashboards/monitoring_grafana_node_dashboard.json https://raw.githubusercontent.com/Florian-94/tpcs-workstations/refs/heads/${tpcsws_branch_name}/terraform-infra/cloudinit/monitoring_grafana_node_dashboard.json"
sudo su - ${username} -c "wget -O /var/tmp/grafana/dashboards/monitoring_grafana_node_full_dashboard.json https://raw.githubusercontent.com/Florian-94/tpcs-workstations/refs/heads/${tpcsws_branch_name}/terraform-infra/cloudinit/monitoring_grafana_node_full_dashboard.json"

# If docker-compose file is not belonging to ${username} it doesn't work and if we want to directly write_file (from cloudinit) in ${username} home directory it breaks compeltely the user creation...
mv /var/tmp/monitoring_docker_compose.yml /home/${username}/monitoring_docker_compose.yml
chown ${username}:${username} /home/${username}/monitoring_docker_compose.yml
sudo su - ${username} -c "docker-compose -f monitoring_docker_compose.yml up -d"
# docker-compose -f monitoring_docker_compose.yml down -v

# Certificate is valid for 90 days, more than enough for our use case - no need to renew
sudo certbot --nginx -d monitoring.tpcsonline.org -d www.monitoring.tpcsonline.org \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'
sudo certbot --nginx -d prometheus.tpcsonline.org -d www.prometheus.tpcsonline.org \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'
sudo certbot --nginx -d grafana.tpcsonline.org -d www.grafana.tpcsonline.org \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'

echo "### Notify end of user_data ###"
touch /home/${username}/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END