#! /bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"

## docs related part #############
sudo certbot --nginx -d docs.tpcs.multiseb.com -d www.docs.tpcs.multiseb.com \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'

# Download a list of files (pdf for the TP)
pip install --upgrade google-api-python-client google-auth-httplib2 google-auth-oauthlib
python3 /var/tmp/gdrive.py
rm -f /var/tmp/token.json
rm -f /var/www/html/index.nginx-debian.html

# Every 5 minutes, run the checks scripts and publish to html file
# echo "*/5 * * * * sudo check_basics > /var/www/html/check_basics.html" | crontab -

# Every 5 minutes run the vms.php script to update vms.html summary
echo "*/5 * * * * root php /root/vms.php > /var/tmp/vms.html && mv /var/tmp/vms.html /var/www/html/vms.html" > /etc/cron.d/php_vm_cron

## access (guacamole) related part #############
echo "git clone guacamole docker compose repo"
sudo su - cloudus -c "git clone https://github.com/boschkundendienst/guacamole-docker-compose.git"

# Certificate is valid for 90 days, more than enough for our use case - no need to renew
sudo certbot --nginx -d access.tpcs.multiseb.com -d www.access.tpcs.multiseb.com \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'

echo "Now launch the docker compose"
sudo su - cloudus -c "cd guacamole-docker-compose && ./prepare.sh"
sudo su - cloudus -c "cd guacamole-docker-compose && docker-compose up -d"

echo "### install Terraform ###"
wget https://releases.hashicorp.com/terraform/1.6.1/terraform_1.6.1_linux_amd64.zip
unzip terraform_1.6.1_linux_amd64.zip
sudo mv terraform /usr/bin
rm terraform_1.6.1_linux_amd64.zip

# Create guacamole config file with content of var
sudo su - cloudus -c "echo \"${guac_tf_file}\" | base64 -d > guac_config.tf"

sudo su - cloudus -c "terraform init"
sudo su - cloudus -c "terraform apply -auto-approve"

# Deploy Prometheus and Grafana
# Grafana Dashboards links for reference
# https://grafana.com/api/dashboards/11133/revisions/2/download
# https://grafana.com/api/dashboards/1860/revisions/37/download
sudo su - cloudus -c "mkdir -p /var/tmp/grafana/dashboards"
sudo su - cloudus -c "wget -O /var/tmp/grafana/dashboards/monitoring_grafana_node_dashboard.json https://raw.githubusercontent.com/seb54000/tpcs-workstations/refs/heads/master/terraform-infra/cloudinit/monitoring_grafana_node_dashboard.json"
sudo su - cloudus -c "wget -O /var/tmp/grafana/dashboards/monitoring_grafana_node_full_dashboard.json https://raw.githubusercontent.com/seb54000/tpcs-workstations/refs/heads/master/terraform-infra/cloudinit/monitoring_grafana_node_full_dashboard.json"

# If docker-compose file is not belonging to cloudus it doesn't work and if we want to directly write_file (from cloudinit) in cloudus home directory it breaks compeltely the user creation...
mv /var/tmp/monitoring_docker_compose.yml /home/cloudus/monitoring_docker_compose.yml
chown cloudus:cloudus /home/cloudus/monitoring_docker_compose.yml
sudo su - cloudus -c "docker-compose -f monitoring_docker_compose.yml up -d"
# docker-compose -f monitoring_docker_compose.yml down -v

# Certificate is valid for 90 days, more than enough for our use case - no need to renew
sudo certbot --nginx -d monitoring.tpcs.multiseb.com -d www.monitoring.tpcs.multiseb.com \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'
sudo certbot --nginx -d prometheus.tpcs.multiseb.com -d www.prometheus.tpcs.multiseb.com \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'z
sudo certbot --nginx -d grafana.tpcs.multiseb.com -d www.grafana.tpcs.multiseb.com \
    --non-interactive --agree-tos \
    --no-eff-email \
    --no-redirect \
    --email 'user@test.com'

echo "### Notify end of user_data ###"
touch /home/cloudus/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END