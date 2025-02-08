#! /bin/bash -xe
# https://alestic.com/2010/12/ubuntu-data-output/
exec > >(tee /var/log/user-data-student.log|logger -t user-data -s 2>/dev/console) 2>&1
echo BEGIN
BEGIN_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"


sudo usermod -a -G microk8s vm${count_number_2digits}
sudo mkdir -p /home/vm${count_number_2digits}/.kube
sudo chown vm${count_number_2digits}:vm${count_number_2digits} /home/vm${count_number_2digits}/.kube

echo "alias k=kubectl" >> ~/.bash_aliases
echo 'complete -F __start_kubectl k' >>~/.bashrc

echo "git clone tp-centrale-repo"
sudo su - vm${count_number_2digits} -c "git clone https://github.com/seb54000/tp-cs-containers-student.git"

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


echo "### Notify end of user_data ###"
touch /home/vm${count_number_2digits}/user_data_student_finished
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "BEGIN_DATE : $BEGIN_DATE"
echo "END_DATE : $END_DATE"
echo END