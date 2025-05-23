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
sudo snap install kubectl --classic
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

echo "git clone tp-centrale-repo"
sudo su - vm${count_number_2digits} -c "git clone https://github.com/seb54000/tp-cs-monitoring-student.git"
sudo su - vm${count_number_2digits} -c "cd tp-cs-monitoring-student && git clone https://github.com/open-telemetry/opentelemetry-demo.git 03-opentelemetry"
# v2.0.2

systemctl stop node_exporter.service
microk8s stop

sudo su - vm${count_number_2digits} -c "pip install flask opentelemetry-sdk opentelemetry-instrumentation-flask \
    opentelemetry-exporter-prometheus opentelemetry-exporter-jaeger \
    opentelemetry-instrumentation-requests prometheus_client"


# This is for xrdp config
# TODO would be nice to have a SAN localhost for certificate and delivered by letsEncrypt or other trusted CA
# https://letsencrypt.org/docs/certificates-for-localhost/
sudo openssl req -x509 -sha384 -newkey rsa:3072 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
# openssl req -x509 -out localhost.crt -keyout localhost.key \
#   -newkey rsa:2048 -nodes -sha256 \
#   -subj '/CN=localhost' -extensions EXT -config <( \
#    printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")




echo "### Install vscode ###"
sudo snap install --classic code # or code-insiders

echo "Install vscode extension for kubernetes and docker"
sudo su - vm${count_number_2digits} -c "code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools"
        # TODO : docker ext is not compatible with snap docker...
sudo su - vm${count_number_2digits} -c "code --install-extension ms-azuretools.vscode-docker"
sudo su - vm${count_number_2digits} -c "code --install-extension pomdtr.excalidraw-editor"
# echo "Install Octant - Kubernetes dashboard"
# sudo yum install -y https://github.com/vmware-tanzu/octant/releases/download/v0.25.1/octant_0.25.1_Linux-64bit.rpm

echo "Install Chromium Extension (auto refresh)"
cat <<EOF > /var/tmp/autorefresh.json
{
    "ExtensionInstallForcelist":
        ["aabcgdmkeabbnleenpncegpcngjpnjkc;https://clients2.google.com/service/update2/crx"]

}
EOF
sudo mkdir -p /var/snap/chromium/current/policies/managed
sudo mv /var/tmp/autorefresh.json /var/snap/chromium/current/policies/managed/autorefresh.json

# Manage xfce browser shortcut to use chromium
sed -i s/Exec.*/Exec=chromium/g /usr/share/applications/xfce4-web-browser.desktop

echo "Start some tools when opening XRDP session"
sudo su - vm${count_number_2digits} -c "mkdir -p /home/vm${count_number_2digits}/.config/autostart/"
cat <<EOF > /var/tmp/vscode.desktop
[Desktop Entry]
Type=Application
Exec=code --disable-workspace-trust /home/vm${count_number_2digits}/tp-cs-monitoring-student/
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
curl -O https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.5.tgz
tar -xzf apache-jmeter-5.5.tgz
sudo mv apache-jmeter-5.5 /usr/local/bin/
rm -f apache-jmeter-5.5.tgz
sudo su - vm${count_number_2digits} -c "echo \"export PATH=/usr/local/bin/apache-jmeter-5.5/bin:\$PATH\" >> ~/.bashrc"


echo "### Notify end of user_data ###"
touch /home/vm${count_number_2digits}/user_data_student_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END