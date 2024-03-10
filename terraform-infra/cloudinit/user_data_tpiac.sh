#! /bin/bash -xe
# https://alestic.com/2010/12/ubuntu-data-output/
exec > >(tee /var/log/user-data-student.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"


sudo apt install xrdp -y
sudo systemctl enable xrdp
sudo usermod -a -G ssl-cert xrdp
sudo systemctl restart xrdp

sudo apt install xfce4 -y

# Remove anoying confirmation for colr manager 
# https://devanswe.rs/how-to-fix-authentication-is-required-to-create-a-color-profile-managed-device-on-ubuntu-20-04-20-10/?utm_content=cmp-true

sudo cat <<EOF > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF


echo "git clone tp-centrale-repo"
sudo su - cloudus -c "git clone https://github.com/seb54000/tpcs-iac.git"


echo "### Setup for TF and ansible environment ###"
sudo su - cloudus -c 'ssh-keygen -N "" -f /home/cloudus/tpcs-iac/vikunja/terraform/tp-iac'
sudo su - cloudus -c cat <<EOF > /home/cloudus/tpcs-iac/.env
# aws console login URL : https://tpiac.signin.aws.amazon.com/console/
# aws console username : "${console_user_name}"
# aws console password : "${console_passwd}"
export AWS_ACCESS_KEY_ID="${access_key}"
export AWS_SECRET_ACCESS_KEY="${secret_key}"
export AWS_DEFAULT_REGION="${region_for_apikey}"
export TF_VAR_ssh_key_public=\$(cat /home/cloudus/tpcs-iac/vikunja/terraform/tp-iac.pub)
EOF

echo "### Setup credential file for AWS cli ###"
sudo su - cloudus -c 'mkdir ~/.aws'
sudo su - cloudus -c cat <<EOF > /home/cloudus/.aws/credentials
[default]
aws_access_key_id = ${access_key}
aws_secret_access_key = ${secret_key}
EOF
sudo su - cloudus -c cat <<EOF > /home/cloudus/.aws/config
[default]
region = ${region_for_apikey}
output = json
EOF

# This is for xrdp config
# TODO would be nice to have a SAN localhost for certificate and delivered by letsEncrypt or other trusted CA
# https://letsencrypt.org/docs/certificates-for-localhost/
sudo openssl req -x509 -sha384 -newkey rsa:3072 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
# openssl req -x509 -out localhost.crt -keyout localhost.key \
#   -newkey rsa:2048 -nodes -sha256 \
#   -subj '/CN=localhost' -extensions EXT -config <( \
#    printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")

echo "### Install vscode ###"
sudo curl -Lo /var/tmp/vscode.deb https://go.microsoft.com/fwlink/?LinkID=760868
sudo apt install -y /var/tmp/vscode.deb

echo "### install Ansible ###"
sudo apt-add-repository -y ppa:ansible/ansible
sudo apt update
sudo apt install -y ansible
sudo apt install -y python3-pip
sudo apt install -y python3.10-venv

echo "### install Terraform ###"
sudo apt install -y unzip
wget https://releases.hashicorp.com/terraform/1.6.1/terraform_1.6.1_linux_amd64.zip
unzip terraform_1.6.1_linux_amd64.zip
sudo mv terraform /usr/bin
rm terraform_1.6.1_linux_amd64.zip


echo "Install some vscode extensions"
sudo su - cloudus -c "code --install-extension redhat.vscode-yaml"
sudo su - cloudus -c "code --install-extension redhat.ansible"
sudo su - cloudus -c "code --install-extension HashiCorp.terraform"
sudo su - cloudus -c "code --install-extension pomdtr.excalidraw-editor"

echo "Install Chrome"
sudo snap install chromium

sudo apt install -y chromium-bsu
echo "Install CHromimum Extension (auto refresh)"
cat <<EOF > /var/tmp/autorefresh.json
{
    "ExtensionInstallForcelist":
        ["aabcgdmkeabbnleenpncegpcngjpnjkc;https://clients2.google.com/service/update2/crx"]

}
EOF
sudo mkdir -p /var/snap/chromium/current/policies/managed
sudo mv /var/tmp/autorefresh.json /var/snap/chromium/current/policies/managed/autorefresh.json

echo "Start some tools when opening XRDP session"
sudo su - cloudus -c "mkdir -p /home/cloudus/.config/autostart/"
cat <<EOF > /var/tmp/vscode.desktop
[Desktop Entry]
Type=Application
Exec=code --disable-workspace-trust /home/cloudus/tpcs-iac/
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=vscode
Name=vscode
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/vscode.desktop /home/cloudus/.config/autostart/
sudo chmod 666 /home/cloudus/.config/autostart/vscode.desktop
cat <<EOF > /var/tmp/mateterminal.desktop
[Desktop Entry]
Type=Application
Exec=/usr/bin/gnome-terminal
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=mateterminal
Name=mateterminal
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/mateterminal.desktop /home/cloudus/.config/autostart/
sudo chmod 666 /home/cloudus/.config/autostart/mateterminal.desktop
cat <<EOF > /var/tmp/chromium.desktop
[Desktop Entry]
Type=Application
Exec=/snap/bin/chromium %U
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=chromium
Name=chromium
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/chromium.desktop /home/cloudus/.config/autostart/
sudo chmod 666 /home/cloudus/.config/autostart/chromium.desktop



echo "### Notify end of user_data ###"
touch /home/ubuntu/user_data_student_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END


