#! /bin/bash -xe
# https://alestic.com/2010/12/ubuntu-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"

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


sudo apt install -y git
echo "git clone tp-centrale-repo"
sudo su - cloudus -c "git clone https://github.com/seb54000/tp-centralesupelec-iac.git"

# This is for xrdp config
# TODO would be nice to have a SAN localhost for certificate and delivered by letsEncrypt or other trusted CA
# https://letsencrypt.org/docs/certificates-for-localhost/
sudo openssl req -x509 -sha384 -newkey rsa:3072 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
# openssl req -x509 -out localhost.crt -keyout localhost.key \
#   -newkey rsa:2048 -nodes -sha256 \
#   -subj '/CN=localhost' -extensions EXT -config <( \
#    printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")

echo "### install htop , tmux ###"
sudo apt install -y htop
echo "### install tmux ###"
sudo apt install -y tmux

echo "### Install vscode ###"
sudo curl -Lo /var/tmp/vscode.deb https://go.microsoft.com/fwlink/?LinkID=760868
sudo apt install -y /var/tmp/vscode.deb

echo "### install Ansible ###"
sudo apt-add-repository -y ppa:ansible/ansible
sudo apt update
sudo apt install -y ansible
sudo apt install -y python3-pip

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
Exec=code --disable-workspace-trust /home/cloudus/tp-centralesupelec-iac/
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


echo "### Stop VM by cronjob at 8pm all day ###"
# (crontab -l 2>/dev/null; echo "00 20 * * * sudo shutdown -h now") | crontab -
echo "00 20 * * * sudo shutdown -h now" | crontab -

echo "### Notify end of user_data ###"
touch /home/ubuntu/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END

=======



sudo yum install -y git

# Get TP framework IAC from googleDrive with shared link
sudo su - iac -c "wget -O tpcentrale.zip \"https://drive.google.com/uc?id=1-RTkiPmk70NgEuRUK98Xbh6t6oEakIhM&export=download\""
sudo su - iac -c "unzip tpcentrale.zip"
sudo su - iac -c "mv centralesupelec-tp tp-iac"
sudo su - iac -c "rm -rf __MACOSX"
sudo su - iac -c "rm -f tpcentrale.zip"
sudo su - iac -c "rm -rf tp-iac/ansible/.git"



