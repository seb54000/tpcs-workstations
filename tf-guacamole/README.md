
https://hub.docker.com/r/maxwaldorf/guacamole

sudo yum install -y docker
mkdir -p /home/rocky/config
docker run -p 8080:8080 -v /home/rocky/config/:/config:Z docker.io/flcontainers/guacamole
#### https://stackoverflow.com/questions/24288616/permission-denied-on-accessing-host-directory-in-docker 

Access on port 8080 et http sur l'IP de la VM, exemple : http://18.207.213.173:8080/
user/pwd are both : guacadmin

AMITEST_IP=$(terraform output -json tpkube-instance-ip | jq -r '.[]')
ssh -o StrictHostKeyChecking=no -i ~/.ssh/guacamole_key rocky@${AMITEST_IP}

ssh -o StrictHostKeyChecking=no -i ~/.ssh/guacamole_key ec2-user@${AMITEST_IP}


## Logs de guacamole
Assez mal foutu mais le tomcat écrit dans un fichier catalina.out


tail -f /opt/tomcat/logs/catalina.out



## Create specific PEM format ssh key for SSH connection test in guacamole
https://github.com/MaxWaldorf/guacamole/issues/8
ssh-keygen -t rsa -b 4096 -m PEM -C "Comment"


## XRDP test

Try with same mono / MATE image as for the rest of TP
    - add same xrdp install tasks in user data


Wuth older ROcky official subscribing image

https://wiki.crowncloud.net/?How_to_Install_Xrdp_with_GNOME_GUI_on_RockyLinux_8

echo "rocky" | sudo passwd rocky --stdin


sudo yum groupinstall -y "Server with GUI"
sudo systemctl set-default graphical

sudo dnf install -y epel-release
sudo dnf install -y xrdp
sudo systemctl start xrdp
sudo systemctl enable xrdp

sudo firewall-cmd --permanent --add-port=3389/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

sudo reboot


ça marche avec un paramétrage basique guacamole xrdp, par contre, c'est assez lent (bien cocher untrust certificate)
C'est pas non plus inutilisable pour les perfs mais par exemple on peut pas regarder une vidéo sur Youtube, ça saccade énormément
Mais il faut tester avec des environnements graphiques plus lights ? Pas sûr que ça change quelque chose
Et le mac local s'emballe pas mal avec un onglet de navigateur qui a ça (après il faudrait tester avec rien d'autre qui tourne en local puisque finalement tout serait distant)


## TODO test VNC + Xfce (gnome est long à installer)
https://techviewleo.com/install-and-configure-vnc-server-on-rocky-linux/

## TODO test avec websocket




à tester : https://github.com/ariesyous/guacamole-aws ??