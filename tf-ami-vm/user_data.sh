#! /bin/bash -xe
# https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN        
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
sudo openssl req -x509 -sha384 -newkey rsa:3072 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
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
echo "### Install Micro k8s ###"
sudo snap install microk8s --classic --channel=1.24
# Install Lens
sudo yum install -y https://api.k8slens.dev/binaries/Lens-6.0.1-latest.20220810.2.x86_64.rpm
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
sudo /var/lib/snapd/snap/bin/microk8s enable dns storage ingress
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

# TODO dinf a way to get a DNS record even when IP change at reboot
# https://medium.com/innovation-incubator/how-to-automatically-update-ip-addresses-without-using-elastic-ips-on-amazon-route-53-4593e3e61c4c
# sudo echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg

echo "### Notify end of user_data ###"
touch /home/ec2-user/user_data_finished
date '+%Y-%m-%d %H:%M:%S'
echo END