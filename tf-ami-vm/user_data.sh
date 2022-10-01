#! /bin/bash -xe
# https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/add-repositories.html
sudo yum update -y
echo "### Snapd install for microk8s install (at beginning for snapd to launch) ###"
sudo yum install -y https://github.com/albuild/snap/releases/download/v0.1.0/snap-confine-2.36.3-0.amzn2.x86_64.rpm
sudo yum install -y https://github.com/albuild/snap/releases/download/v0.1.0/snapd-2.36.3-0.amzn2.x86_64.rpm        
sudo systemctl enable snapd
sudo systemctl start snapd  
echo "### Add passwd, create user, finalize xrdp config ###"
echo "${ec2_user_passwd}" | sudo passwd ec2-user --stdin
sudo useradd cloudus 
echo "${cloudus_user_passwd}" | sudo passwd cloudus --stdin
sudo usermod -aG wheel cloudus
# Nice way to avoid cloudus ask for password when doing sudo (so relax for testing env)
echo "cloudus ALL=(ALL) NOPASSWD:ALL" | (sudo su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/cloudus')
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
echo "### install docker ###"
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
sudo usermod -aG docker cloudus     
echo "### kubectl install ###"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl completion bash > kubectl.bash
sudo mv kubectl.bash /etc/bash_completion.d/

echo "### Install Micro k8s ###"
sudo snap install microk8s --classic --channel=1.24
# Install Lens
sudo snap install kontena-lens --classic # This way we have a 4.x version without subscription !
# sudo yum install -y https://api.k8slens.dev/binaries/Lens-6.0.1-latest.20220810.2.x86_64.rpm
echo "### Install POSTMAN ###"
sudo snap install postman
echo "### Install Insomnia (POSTMAN free equivalent) ###"
sudo snap install insomnia
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
# echo "### Microk8s configuration finalization ###"
sudo usermod -a -G microk8s ec2-user
sudo usermod -a -G microk8s cloudus
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
sudo /var/lib/snapd/snap/bin/microk8s enable dns hostpath-storage ingress
sudo mkdir -p /home/ec2-user/.kube
sudo cp /var/snap/microk8s/current/credentials/client.config /home/ec2-user/.kube/config
sudo chown ec2-user:ec2-user /home/ec2-user/.kube/config
sudo chown -f -R ec2-user ~/.kube
sudo mkdir -p /home/cloudus/.kube
sudo chown cloudus:cloudus /home/cloudus/.kube
sudo cp /var/snap/microk8s/current/credentials/client.config /home/cloudus/.kube/config
sudo chown cloudus:cloudus /home/cloudus/.kube/config
sudo chown -f -R cloudus ~/.kube
# echo "### MiniKube install ###"
# curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
# sudo install minikube-linux-amd64 /usr/local/bin/minikube
echo "git clone tp-centrale-repo"
sudo yum install -y git
sudo su - ec2-user -c "git clone https://github.com/seb54000/tp-centralesupelec.git tp-kube"
sudo su - cloudus -c "git clone https://github.com/seb54000/tp-centralesupelec.git tp-kube"

# Get a DNS record even when IP change at reboot
# https://medium.com/innovation-incubator/how-to-automatically-update-ip-addresses-without-using-elastic-ips-on-amazon-route-53-4593e3e61c4c
sudo curl -o /var/lib/cloud/scripts/per-boot/dns_set_record.sh https://raw.githubusercontent.com/seb54000/tp-centralesupelec/master/tf-ami-vm/dns_set_record.sh
sudo chmod 755 /var/lib/cloud/scripts/per-boot/dns_set_record.sh

echo "Install vscode extension for kubernetes and docker"
sudo su - ec2-user -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - cloudus -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
sudo su - ec2-user -c "code --install-extension ms-azuretools.vscode-docker"
sudo su - cloudus -c "code --install-extension ms-azuretools.vscode-docker"
echo "Install Octant - Kubernetes dashboard"
sudo yum install -y https://github.com/vmware-tanzu/octant/releases/download/v0.25.1/octant_0.25.1_Linux-64bit.rpm

echo "Install CHromimum Extension (auto refresh)"
cat <<EOF > /var/tmp/autorefresh.json
{
    "ExtensionInstallForcelist":
        ["aabcgdmkeabbnleenpncegpcngjpnjkc;https://clients2.google.com/service/update2/crx"]

}
EOF
sudo mv /var/tmp/autorefresh.json /etc/chromium/policies/managed/autorefresh.json

echo "Start some tools when opening XRDP session"
sudo su - cloudus -c "mkdir -p /home/cloudus/.config/autostart/"
cat <<EOF > /var/tmp/vscode.desktop
[Desktop Entry]
Type=Application
Exec=code --disable-workspace-trust /home/cloudus/tp-kube/
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
Exec=mate-terminal
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
Exec=/usr/bin/chromium-browser %U
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
sudo su - cloudus -c "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
sudo su - ec2-user -c "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
sudo su - cloudus -c "helm repo add bitnami https://charts.bitnami.com/bitnami"
sudo su - ec2-user -c "helm repo add bitnami https://charts.bitnami.com/bitnami"

curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz"
tar zxvf "krew-linux_amd64.tar.gz"
cp krew-linux_amd64 /var/tmp/krew-linux_amd64
chmod 755 /var/tmp/krew-linux_amd64
./krew-linux_amd64 install krew
sudo su - cloudus -c "/var/tmp/krew-linux_amd64 install krew"
sudo su - cloudus -c "echo \"export PATH=\"\$PATH:\$HOME/.krew/bin\"\" >> ~/.bashrc"
sudo su - ec2-user -c "echo \"export PATH=\"\$PATH:\$HOME/.krew/bin\"\" >> ~/.bashrc"
rm -f krew-linux_amd64  krew-linux_amd64.tar.gz  LICENSE /var/tmp/krew-linux_amd64

echo "Install Wireshark and ksniff"
sudo yum install -y wireshark-gnome
sudo usermod -a -G wireshark cloudus
sudo usermod -a -G wireshark ec2-user
sudo su - cloudus -c "kubectl krew install sniff"
# sudo su - ec2-user -c "kubectl krew install sniff"

echo "Install Java and Jmeter"
sudo yum install -y java-1.8.0-openjdk
curl -O https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.5.tgz
tar -xzf apache-jmeter-5.5.tgz
sudo mv apache-jmeter-5.5 /usr/local/bin/
rm -f apache-jmeter-5.5.tgz
sudo su - ec2-user -c "echo \"PATH=/usr/local/bin/apache-jmeter-5.5/bin:\$PATH\" >> ~/.bashrc"
sudo su - cloudus -c "echo \"PATH=/usr/local/bin/apache-jmeter-5.5/bin:\$PATH\" >> ~/.bashrc"

echo "Install jq and yq"
sudo yum install -y jq
sudo snap install yq

echo "Allow PasswordAuthentication for SSH - for easier use"
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl restart sshd

echo "### Notify end of user_data ###"
touch /home/ec2-user/user_data_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END