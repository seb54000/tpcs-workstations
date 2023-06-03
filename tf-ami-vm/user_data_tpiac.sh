#! /bin/bash -xe
# https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/add-repositories.html

sudo yum update -y

# echo "### Snapd install for microk8s install (at beginning for snapd to launch) ###"
# sudo yum install -y https://github.com/albuild/snap/releases/download/v0.1.0/snap-confine-2.36.3-0.amzn2.x86_64.rpm
# sudo yum install -y https://github.com/albuild/snap/releases/download/v0.1.0/snapd-2.36.3-0.amzn2.x86_64.rpm        
# sudo systemctl enable snapd
# sudo systemctl start snapd  

echo "### Add passwd, create user, finalize xrdp config ###"
echo "${ec2_user_passwd}" | sudo passwd ec2-user --stdin
sudo useradd iac 
echo "${iac_user_passwd}" | sudo passwd iac --stdin
sudo usermod -aG wheel iac
# Nice way to avoid iac ask for password when doing sudo (so relax for testing env)
echo "iac ALL=(ALL) NOPASSWD:ALL" | (sudo su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/iac')

# This is for xrdp config
# TODO would be nice to have a SAN localhost for certificate and delivered by letsEncrypt or other trusted CA
# https://letsencrypt.org/docs/certificates-for-localhost/
sudo openssl req -x509 -sha384 -newkey rsa:3072 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
# openssl req -x509 -out localhost.crt -keyout localhost.key \
#   -newkey rsa:2048 -nodes -sha256 \
#   -subj '/CN=localhost' -extensions EXT -config <( \
#    printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
echo "### install htop ###"
sudo yum install -y htop

# Install ansible and terraform 
wget https://releases.hashicorp.com/terraform/1.3.7/terraform_1.3.7_linux_amd64.zip
unzip terraform_1.3.7_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm -f terraform_1.3.7_linux_amd64.zip

sudo yum install -y ansible


echo "### Restart for xrdp to work again ###"
sudo systemctl restart xrdp
echo "### Install vscode ###"
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat <<EOF > /var/tmp/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
sudo mv /var/tmp/vscode.repo /etc/yum.repos.d/vscode.repo
sudo yum install -y code

sudo yum install -y git

# Get TP framework IAC from googleDrive with shared link
sudo su - iac -c "wget -O tpcentrale.zip \"https://drive.google.com/uc?id=1-RTkiPmk70NgEuRUK98Xbh6t6oEakIhM&export=download\""
sudo su - iac -c "unzip tpcentrale.zip"
sudo su - iac -c "mv centralesupelec-tp tp-iac"
sudo su - iac -c "rm -rf __MACOSX"
sudo su - iac -c "rm -f tpcentrale.zip"
sudo su - iac -c "rm -rf tp-iac/ansible/.git"

# Get a DNS record even when IP change at reboot
# https://medium.com/innovation-incubator/how-to-automatically-update-ip-addresses-without-using-elastic-ips-on-amazon-route-53-4593e3e61c4c
sudo curl -o /var/lib/cloud/scripts/per-boot/dns_set_record.sh https://raw.githubusercontent.com/seb54000/tp-centralesupelec/master/tf-ami-vm/dns_set_record.sh
sudo chmod 755 /var/lib/cloud/scripts/per-boot/dns_set_record.sh

# TODO install ansible, terraform, and ssh remote extension...
echo "Install vscode extension for kubernetes and docker"
sudo su - ec2-user -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - iac -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - ec2-user -c "code --install-extension ms-azuretools.vscode-docker"
sudo su - iac -c "code --install-extension ms-azuretools.vscode-docker"



echo "Install CHromimum Extension (auto refresh)"
cat <<EOF > /var/tmp/autorefresh.json
{
    "ExtensionInstallForcelist":
        ["aabcgdmkeabbnleenpncegpcngjpnjkc;https://clients2.google.com/service/update2/crx"]

}
EOF
sudo mv /var/tmp/autorefresh.json /etc/chromium/policies/managed/autorefresh.json

echo "Start some tools when opening XRDP session"
sudo su - iac -c "mkdir -p /home/iac/.config/autostart/"
cat <<EOF > /var/tmp/vscode.desktop
[Desktop Entry]
Type=Application
Exec=code --disable-workspace-trust /home/iac/tp-iac/
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=vscode
Name=vscode
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/vscode.desktop /home/iac/.config/autostart/
sudo chmod 666 /home/iac/.config/autostart/vscode.desktop
cat <<EOF > /var/tmp/mateterminal.desktop
[Desktop Entry]
Type=Application
Exec=mate-terminal
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=mateterminal
Name=mateterminal
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/mateterminal.desktop /home/iac/.config/autostart/
sudo chmod 666 /home/iac/.config/autostart/mateterminal.desktop
cat <<EOF > /var/tmp/chromium.desktop
[Desktop Entry]
Type=Application
Exec=/usr/bin/chromium-browser %U
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=chromium
Name=chromium
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/chromium.desktop /home/iac/.config/autostart/
sudo chmod 666 /home/iac/.config/autostart/chromium.desktop

echo "Install jq and yq"
sudo yum install -y jq
# sudo snap install yq   # See if needed as this is the ony tool needing snap (that we comment at the top for install)

echo "Allow PasswordAuthentication for SSH - for easier use"
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl restart sshd

echo "### Notify end of user_data ###"
touch /home/ec2-user/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END