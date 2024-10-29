#! /bin/bash -xe
# https://alestic.com/2010/12/ubuntu-data-output/
exec > >(tee /var/log/user-data-student.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"


# sudo snap install microk8s --classic
# sudo snap install microk8s --classic --channel=1.27
sudo microk8s enable dns hostpath-storage ingress registry
# microk8s enable metallb:10.64.140.43-10.64.140.49
sudo usermod -aG microk8s vm${count_number_2digits}
# newgrp microk8s




echo "### kubectl install ###"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl completion bash > kubectl.bash
sudo mv kubectl.bash /etc/bash_completion.d/
sudo su - vm${count_number_2digits} -c "echo \"alias k='kubectl'\" >> ~/.bash_aliases"

sudo mkdir -p /home/vm${count_number_2digits}/.kube
sudo chown vm${count_number_2digits}:vm${count_number_2digits} /home/vm${count_number_2digits}/.kube
sudo cp /var/snap/microk8s/current/credentials/client.config /home/vm${count_number_2digits}/.kube/config
sudo chown vm${count_number_2digits}:vm${count_number_2digits} /home/vm${count_number_2digits}/.kube/config
sudo chown -f -R vm${count_number_2digits} ~/.kube
sudo chmod 600 /home/vm${count_number_2digits}/.kube/config

# echo "### install docker ###"
# sudo groupadd docker
# sudo snap install docker
sudo usermod -aG docker vm${count_number_2digits}

# sudo newgrp docker # Or reboot will be needed on a VM... https://docs.docker.com/engine/install/linux-postinstall/


sudo apt install xrdp -y
sudo systemctl enable xrdp
sudo usermod -a -G ssl-cert xrdp
sudo systemctl restart xrdp

sudo apt install xfce4 -y


echo "alias k=kubectl" >> ~/.bash_aliases
echo 'complete -F __start_kubectl k' >>~/.bashrc

# echo "git clone tp-centrale-repo"
# sudo apt install -y git
# sudo su - vm${count_number_2digits} -c "git clone https://github.com/seb54000/tp-centralesupelec.git tp-kube"
echo "git clone tp-centrale-repo"
sudo su - vm${count_number_2digits} -c "git clone https://github.com/seb54000/tp-cs-containers-student.git"



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




# Install Lens
# TODO pb not working anymore lens install
# sudo snap install kontena-lens --classic # This way we have a 4.x version without subscription !
# sudo yum install -y https://api.k8slens.dev/binaries/Lens-6.0.1-latest.20220810.2.x86_64.rpm
# echo "### Install POSTMAN ###"
# sudo snap install postman
# echo "### Install Insomnia (POSTMAN free equivalent) ###"
# sudo snap install insomnia
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
# sudo usermod -a -G microk8s vm${count_number_2digits}
# export LC_ALL=C.UTF-8
# export LANG=C.UTF-8






echo "Install vscode extension for kubernetes and docker"
sudo su - vm${count_number_2digits} -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - vm${count_number_2digits} -c "code --install-extension ms-azuretools.vscode-docker"
sudo su - vm${count_number_2digits} -c "code --install-extension pomdtr.excalidraw-editor"
# echo "Install Octant - Kubernetes dashboard"
# sudo yum install -y https://github.com/vmware-tanzu/octant/releases/download/v0.25.1/octant_0.25.1_Linux-64bit.rpm

echo "Install Chrome"
# sudo snap install chromium

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
sudo su - vm${count_number_2digits} -c "mkdir -p /home/vm${count_number_2digits}/.config/autostart/"
cat <<EOF > /var/tmp/vscode.desktop
[Desktop Entry]
Type=Application
Exec=code --disable-workspace-trust /home/vm${count_number_2digits}/tp-cs-containers-student/
Hidden=false
X-MATE-Autostart-enabled=true
Name[en_US]=vscode
Name=vscode
Comment[en_US]=
Comment=
X-MATE-Autostart-Delay=0
EOF
sudo mv /var/tmp/vscode.desktop /home/vm${count_number_2digits}/.config/autostart/
sudo chmod 666 /home/vm${count_number_2digits}/.config/autostart/vscode.desktop
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
sudo mv /var/tmp/mateterminal.desktop /home/vm${count_number_2digits}/.config/autostart/
sudo chmod 666 /home/vm${count_number_2digits}/.config/autostart/mateterminal.desktop
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
sudo mv /var/tmp/chromium.desktop /home/vm${count_number_2digits}/.config/autostart/
sudo chmod 666 /home/vm${count_number_2digits}/.config/autostart/chromium.desktop

echo "Install krew and helm"
# sudo snap install helm --classic
sudo su - vm${count_number_2digits} -c "helm repo add bitnami https://charts.bitnami.com/bitnami"

echo "Install k9s - terminal based UI for k8s"
curl -Lo /var/tmp/k9s.tgz https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_amd64.tar.gz
tar -xzf /var/tmp/k9s.tgz
rm /var/tmp/k9s.tgz
mv k9s /usr/local/bin/

(
  TMP_DIR=$(mktemp -d)
  set -x; cd "$TMP_DIR" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz" &&
  tar zxvf "krew-linux_amd64.tar.gz" &&
  chmod -R 777 $TMP_DIR &&
  sudo su - vm${count_number_2digits} -c "$TMP_DIR/krew-linux_amd64 install krew"
)
sudo su - vm${count_number_2digits} -c "echo \"export PATH=/home/vm${count_number_2digits}/.krew/bin:\$PATH\" >> ~/.bashrc"
# Need to do this to use krew now in the script
export PATH=/home/vm${count_number_2digits}/.krew/bin:$PATH

echo "Install Wireshark and ksniff"
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install wireshark
# sudo apt install -y wireshark-gnome
# sudo usermod -a -G wireshark vm${count_number_2digits}
        ## TODO fix this ....   sudo su - vm${count_number_2digits} -c "kubectl krew install sniff"
# sudo su - ubuntu -c "kubectl krew install sniff"

echo "Install Java and Jmeter"
sudo apt install -y openjdk-8-jdk
curl -O https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.5.tgz
tar -xzf apache-jmeter-5.5.tgz
sudo mv apache-jmeter-5.5 /usr/local/bin/
rm -f apache-jmeter-5.5.tgz
sudo su - vm${count_number_2digits} -c "echo \"PATH=/usr/local/bin/apache-jmeter-5.5/bin:\$PATH\" >> ~/.bashrc"


echo "### Notify end of user_data ###"
touch /home/vm${count_number_2digits}/user_data_student_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END