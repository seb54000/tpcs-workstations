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


sudo snap install microk8s --classic
# sudo snap install microk8s --classic --channel=1.27
sudo microk8s enable dns hostpath-storage ingress registry
# microk8s enable metallb:10.64.140.43-10.64.140.49
sudo usermod -a -G microk8s ubuntu
sudo usermod -aG microk8s cloudus
sudo mkdir -p ubuntu ~/.kube
sudo chown -R ubuntu ~/.kube
# newgrp microk8s




echo "### kubectl install ###"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl completion bash > kubectl.bash
sudo mv kubectl.bash /etc/bash_completion.d/
sudo su - cloudus -c "echo \"alias k='kubectl'\" >> ~/.bash_aliases"

sudo mkdir -p /home/ubuntu/.kube
sudo cp /var/snap/microk8s/current/credentials/client.config /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config
sudo chown -f -R ubuntu ~/.kube
sudo chmod 600 /home/ubuntu/.kube/config
sudo mkdir -p /home/cloudus/.kube
sudo chown cloudus:cloudus /home/cloudus/.kube
sudo cp /var/snap/microk8s/current/credentials/client.config /home/cloudus/.kube/config
sudo chown cloudus:cloudus /home/cloudus/.kube/config
sudo chown -f -R cloudus ~/.kube
sudo chmod 600 /home/cloudus/.kube/config

echo "### install docker ###"
sudo groupadd docker
sudo snap install docker
sudo usermod -aG docker ubuntu
sudo usermod -aG docker cloudus

sudo newgrp docker # Or reboot will be needed on a VM... https://docs.docker.com/engine/install/linux-postinstall/


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

echo "alias k=kubectl" >> ~/.bash_aliases
echo 'complete -F __start_kubectl k' >>~/.bashrc

# echo "git clone tp-centrale-repo"
sudo apt install -y git
# sudo su - ubuntu -c "git clone https://github.com/seb54000/tp-centralesupelec.git tp-kube"
# sudo su - cloudus -c "git clone https://github.com/seb54000/tp-centralesupelec.git tp-kube"
echo "git clone tp-centrale-repo"
sudo su - cloudus -c "git clone https://github.com/seb54000/tp-cs-containers-student.git"



# On ubuntu, need to install aws CLI
sudo apt install -y awscli
# Get a DNS record even when IP change at reboot
# https://medium.com/innovation-incubator/how-to-automatically-update-ip-addresses-without-using-elastic-ips-on-amazon-route-53-4593e3e61c4c
# sudo curl -o /var/lib/cloud/scripts/per-boot/dns_set_record.sh https://raw.githubusercontent.com/seb54000/tp-centralesupelec/master/tf-ami-vm/dns_set_record.sh
# sudo chmod 755 /var/lib/cloud/scripts/per-boot/dns_set_record.sh
# WE WILL NOW use EIP to keep an external IP adress even after reboot as records are now directly managed in OVH and not through route53...
# TODO : find a way to update records. We can stick to route53 hosted Zone but it costs 0,5 $ each time you create one (so while testing, it may cost a lot. It seems if you delete it within 12 hours, it costs nothing)
# Problem is without route53, it needs wide token (whole OVH zone) in a script on the machine (available to the student....)

# Grrr.... EIP are limited to 5 by account (don't know if we can upgrade this quota)
# Other painpoint is it may need a VPC (whic may not be a bad thing for the future but needs refactoring)
# Anyway lete's try to begin with this method with the risk of public IP dynamically assigned is changing after reboot
#       public IP change only when start/stop (not reboot) https://stackoverflow.com/questions/55414302/an-ip-address-of-ec2-instance-gets-changed-after-the-restart
#       This only means that when VMs are shutdown after day1, we have to launch again terraform at begining of day 2 to start up the Vms and update the DNS records


# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/add-repositories.html

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


# Install Lens
# TODO pb not working anymore lens install
# sudo snap install kontena-lens --classic # This way we have a 4.x version without subscription !
# sudo yum install -y https://api.k8slens.dev/binaries/Lens-6.0.1-latest.20220810.2.x86_64.rpm
echo "### Install POSTMAN ###"
sudo snap install postman
echo "### Install Insomnia (POSTMAN free equivalent) ###"
sudo snap install insomnia
# echo "### Restart for xrdp to work again ###"
# sudo systemctl restart xrdp
echo "### Install vscode ###"

sudo curl -Lo /var/tmp/vscode.deb https://go.microsoft.com/fwlink/?LinkID=760868
sudo apt install -y /var/tmp/vscode.deb


# sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
# cat <<EOF > /var/tmp/vscode.repo
# [code]
# name=Visual Studio Code
# baseurl=https://packages.microsoft.com/yumrepos/vscode
# enabled=1
# gpgcheck=1
# gpgkey=https://packages.microsoft.com/keys/microsoft.asc
# EOF
# sudo mv /var/tmp/vscode.repo /etc/yum.repos.d/vscode.repo
# sudo yum install -y code

# # echo "### Microk8s configuration finalization ###"
# sudo usermod -a -G microk8s ubuntu
# sudo usermod -a -G microk8s cloudus
# export LC_ALL=C.UTF-8
# export LANG=C.UTF-8






echo "Install vscode extension for kubernetes and docker"
sudo su - ubuntu -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - cloudus -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - ubuntu -c "code --install-extension ms-azuretools.vscode-docker"
sudo su - cloudus -c "code --install-extension ms-azuretools.vscode-docker"
sudo su - ubuntu -c "code --install-extension pomdtr.excalidraw-editor"
sudo su - cloudus -c "code --install-extension pomdtr.excalidraw-editor"
# echo "Install Octant - Kubernetes dashboard"
# sudo yum install -y https://github.com/vmware-tanzu/octant/releases/download/v0.25.1/octant_0.25.1_Linux-64bit.rpm

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
Exec=code --disable-workspace-trust /home/cloudus/tp-cs-containers-student/
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

echo "Install krew and helm"
sudo snap install helm --classic
sudo su - cloudus -c "helm repo add bitnami https://charts.bitnami.com/bitnami"
sudo su - ubuntu -c "helm repo add bitnami https://charts.bitnami.com/bitnami"


(
  TMP_DIR=$(mktemp -d)
  set -x; cd "$TMP_DIR" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz" &&
  tar zxvf "krew-linux_amd64.tar.gz" &&
  chmod -R 777 $TMP_DIR &&
  sudo su - cloudus -c "$TMP_DIR/krew-linux_amd64 install krew"
)
sudo su - cloudus -c "echo \"export PATH=/home/cloudus/.krew/bin:\$PATH\" >> ~/.bashrc"
# Need to do this to use krew now in the script
export PATH=/home/cloudus/.krew/bin:$PATH

echo "Install Wireshark and ksniff"
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install wireshark
# sudo apt install -y wireshark-gnome
# sudo usermod -a -G wireshark cloudus
# sudo usermod -a -G wireshark ubuntu
        ## TODO fix this ....   sudo su - cloudus -c "kubectl krew install sniff"
# sudo su - ubuntu -c "kubectl krew install sniff"

echo "Install Java and Jmeter"
sudo apt install -y openjdk-8-jdk
curl -O https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.5.tgz
tar -xzf apache-jmeter-5.5.tgz
sudo mv apache-jmeter-5.5 /usr/local/bin/
rm -f apache-jmeter-5.5.tgz
sudo su - ubuntu -c "echo \"PATH=/usr/local/bin/apache-jmeter-5.5/bin:\$PATH\" >> ~/.bashrc"
sudo su - cloudus -c "echo \"PATH=/usr/local/bin/apache-jmeter-5.5/bin:\$PATH\" >> ~/.bashrc"

echo "### Stop VM by cronjob at 8pm all day ###"
# (crontab -l 2>/dev/null; echo "00 20 * * * sudo shutdown -h now") | crontab -
echo "00 20 * * * sudo shutdown -h now" | crontab -

echo "### Notify end of user_data ###"
touch /home/ubuntu/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END