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



# echo "git clone tp-centrale-repo"
sudo apt install -y git
# sudo su - cloudus -c "git clone https://github.com/seb54000/tp-centralesupelec.git"

echo "git clone tp-centrale-repo"
# sudo su - cloudus -c "git clone https://github.com/seb54000/tp-cs-containers-student.git"

sudo su - cloudus -c "git clone https://github.com/ArnaultMICHEL/guacamole-compose.git"




echo "### install htop , tmux ###"
sudo apt install -y htop
echo "### install tmux ###"
sudo apt install -y tmux



# TODO decide if we keep or update the repo
# We need 12 characters for guac passwd at least
# sed -i -e "s|GUACAMOLE_ADMIN_TEMP_PASSWORD=\\$(openssl rand -base64 8 | tr -d '=')|GUACAMOLE_ADMIN_TEMP_PASSWORD=\\$(openssl rand -base64 12 | tr -d '=')|g"   \
#     /home/cloudus/guacamole-compose/.load.env
sed -i -e 's/8/12/g' /home/cloudus/guacamole-compose/.load.env

sudo su - cloudus -c "cd /home/cloudus/guacamole-compose && source .load.env"
#  cd guacamole
#  source .load.env

#  edit .env result
#  GUAC_HOSTNAME=guacamole.rfa.net > GUAC_HOSTNAME=guacamole.rfa.net
# KC_HOSTNAME=keycloak.rfa.net    KC_HOSTNAME=keycloak.tpiac.multiseb.com

# TODO use variable here instead of fixed values
echo -e "\n Modifying .env with HOSTNAME FQDNs"
sed -i -e "s|GUAC_HOSTNAME=guacamole.rfa.net|GUAC_HOSTNAME=guacamole.tpiac.multiseb.com|g"   \
       -e "s|KC_HOSTNAME=keycloak.rfa.net|KC_HOSTNAME=keycloak.tpiac.multiseb.com|g" \
    /home/cloudus/guacamole-compose/.env


# source .env
# echo "127.0.1.1 $${GUAC_HOSTNAME} $${KC_HOSTNAME}" >>/etc/hosts

# Need keytool
sudo apt install -y openjdk-11-jre-headless

sudo su - cloudus -c "cd /home/cloudus/guacamole-compose && ./setup.sh" # source .load.env is already including in setup.sh
# ./setup.sh

sudo su - cloudus -c "rm -rf /home/cloudus/guacamole-compose/init" # because sometimes frontend is not working well and we have to reinit
sudo su - cloudus -c "cd /home/cloudus/guacamole-compose && ./setup.sh" # because sometimes frontend is not working well and we have to reinit
sudo su - cloudus -c "cd /home/cloudus/guacamole-compose && docker compose up -d"


sudo apt install -y unzip
echo "### install Terraform ###"
sudo apt install -y unzip
wget https://releases.hashicorp.com/terraform/1.6.1/terraform_1.6.1_linux_amd64.zip
unzip terraform_1.6.1_linux_amd64.zip
sudo mv terraform /usr/bin
rm terraform_1.6.1_linux_amd64.zip


# TODO sed to add the auto approve in the script
# Add also a sed to add export before all ines in .env

sudo su - cloudus -c "sed '/^$/d' /home/cloudus/guacamole-compose/.env > /home/cloudus/guacamole-compose/.env.exported"
sudo su - cloudus -c "sed -i -r -e '/^#/ ! s/(.*)/export \1/g' /home/cloudus/guacamole-compose/.env.exported"
sudo su - cloudus -c "sed -i -e 's/apply/apply -auto-approve/' /home/cloudus/guacamole-compose/config/keycloak/1.init-keycloak-realm.sh"

# TODO, need to wait until keycloak is fully started
sleep 5

sudo su - cloudus -c "cd /home/cloudus/guacamole-compose/config/keycloak && source /home/cloudus/guacamole-compose/.env.exported && ./1.init-keycloak-realm.sh"
sudo su - cloudus -c "cd /home/cloudus/guacamole-compose/config/guacamole && source /home/cloudus/guacamole-compose/.env.exported && ./1.manage-guacamole-config.sh"

# TODO decide with arnault if export need to beadded...
# otherwise, worlaround : export $(cut -d= -f1 ../../.env)
# TODO , warning need to source .env before in order to have passwd and other variables
# Need to put terraform in auto approve mode in the script
# # cd config/keycloak
# # ./1.init-keycloak-realm.sh
# # cd config/guacamole
# # ./1.manage-guacamole-config.sh

# https://github.com/ArnaultMICHEL/guacamole-compose/blob/6cd2022d90e5bfe47fb57da4ec77cc65cdcd6e19/.load.env#L19
# Need a 12 pasword character for guacamole admin, actually set to 8, don't know why, to see with arnault and test


# TODO use another terraform template to create a new file , we can do this directly from cloud init
# This file will be used by guacamole  terraform code to create the RDP connexions and users (using the same credentails as for IAM console)
# We may need to delete in keycloak the obligation of changing the password

echo "### Notify end of user_data ###"
touch /home/ubuntu/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END