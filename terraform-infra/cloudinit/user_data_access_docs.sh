#! /bin/bash -xe
# https://alestic.com/2010/12/ubuntu-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"


#######################################################
## docs related part #############
#######################################################


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


#######################################################
## access (guacamole) related part #############
#######################################################

echo "git clone guacamole docker compose repo"

# Create file with content of var
sudo su - cloudus -c "echo \"${guac_tf_file}\" | base64 -d > guac_config.tf"


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

# https://access.tpcs.multiseb.com
# http://access.tpcs.multiseb.com

sudo apt install -y unzip
echo "### install Terraform ###"
wget https://releases.hashicorp.com/terraform/1.6.1/terraform_1.6.1_linux_amd64.zip
unzip terraform_1.6.1_linux_amd64.zip
sudo mv terraform /usr/bin
rm terraform_1.6.1_linux_amd64.zip

# Create guacamole config file with content of var
sudo su - cloudus -c "echo \"${guac_tf_file}\" | base64 -d > guac_config.tf"

sudo su - cloudus -c "terraform init"
sudo su - cloudus -c "terraform apply -auto-approve"



#######################################################
## generic/common related part #############
#######################################################


echo "### Stop VM by cronjob at 8pm all day ###"
# (crontab -l 2>/dev/null; echo "00 20 * * * sudo shutdown -h now") | crontab -
echo "00 20 * * * sudo shutdown -h now" | crontab -

echo "### Notify end of user_data ###"
touch /home/cloudus/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END