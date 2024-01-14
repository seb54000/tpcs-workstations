#! /bin/bash -xe
# https://alestic.com/2010/12/ubuntu-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"

echo "### Set new hostname ###"
sudo hostnamectl set-hostname "${hostname_new}"

echo "### Add passwd, create user, finalize xrdp config ###"
sudo useradd -m -s /bin/bash cloudus
echo "cloudus:${cloudus_user_passwd}" | sudo chpasswd
# Nice way to avoid cloudus ask for password when doing sudo (so relax for testing env)
echo "cloudus ALL=(ALL) NOPASSWD:ALL" | (sudo su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/cloudus')

echo "Allow PasswordAuthentication for SSH - for easier use"
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl restart sshd


sudo apt update
echo "Install jq and yq"
sudo apt install jq -y
sudo snap install yq

sudo apt install net-tools -y

echo "### install docker ###"
sudo groupadd docker
sudo snap install docker
sudo usermod -aG docker ubuntu
sudo usermod -aG docker cloudus

sudo newgrp docker # Or reboot will be needed on a VM... https://docs.docker.com/engine/install/linux-postinstall/




sudo apt install -y git
echo "git clone guacamole docker compose repo"

# Create file with content of var
sudo su - cloudus -c "echo \"${guac_tf_file}\" | base64 -d > guac_config.tf"



sudo su - cloudus -c "git clone https://github.com/boschkundendienst/guacamole-docker-compose.git"


echo "Manage nginx configuration to listen to HTTP only and on default HTTPS port"

sed -i '/listen       443 ssl http2;/i\listen      80;' /home/cloudus/guacamole-docker-compose/nginx/templates/guacamole.conf.template
sed -i '/- 8443:443/{s/- 8443:443/- 443:443\n   - 80:80/}' /home/cloudus/guacamole-docker-compose/docker-compose.yml
sed -i '/.\/nginx\/templates:\/etc\/nginx\/templates:ro/{n;s/.*/&\n   - .\/nginx\/templates:\/etc\/nginx\/conf.d\/:rw/}' /home/cloudus/guacamole-docker-compose/docker-compose.yml

echo "Now launch the docker compose"
sudo su - cloudus -c "cd guacamole-docker-compose && ./prepare.sh"
sudo su - cloudus -c "cd guacamole-docker-compose && docker-compose up -d"

# https://access.tpcs.multiseb.com
# http://access.tpcs.multiseb.com

echo "### install htop , tmux ###"
sudo apt install -y htop
echo "### install tmux ###"
sudo apt install -y tmux




sudo apt install -y unzip
echo "### install Terraform ###"
sudo apt install -y unzip
wget https://releases.hashicorp.com/terraform/1.6.1/terraform_1.6.1_linux_amd64.zip
unzip terraform_1.6.1_linux_amd64.zip
sudo mv terraform /usr/bin
rm terraform_1.6.1_linux_amd64.zip


# Create file with content of var
sudo su - cloudus -c "echo \"${guac_tf_file}\" | base64 -d > guac_config.tf"

sudo su - cloudus -c "terraform init"
sudo su - cloudus -c "terraform apply -auto-approve"




echo "### Stop VM by cronjob at 8pm all day ###"
# (crontab -l 2>/dev/null; echo "00 20 * * * sudo shutdown -h now") | crontab -
echo "00 20 * * * sudo shutdown -h now" | crontab -

echo "### Notify end of user_data ###"
touch /home/ubuntu/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END