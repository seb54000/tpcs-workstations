### You need to have locally downloaded UBUNTU images before (not interesting to commit those 5 GB file in github...)

k8sgui : https://drive.google.com/file/d/1hWm12deQDGXaGtEXHdNizWv6JW4fEKe0/view?usp=sharing
k8s : https://drive.google.com/file/d/1O9gVBEvuYVmTQzHu8ujvzR0jlYYtt0cX/view?usp=sharing



### Then convert ova image in .tar and use any archive tool to extract only .vmdk files

You should have in your local folder : 
k8s-disk001.vmdk
k8sgui-disk001.vmdk



TODO : store vmdk files in google cloud drive then use http provider from terraform to download them before upload to s3
https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http

Not sure it is worth the effort, so still TODO


--- Difficile de faire marcher le XRDP, mes notes en boruillon pour le moment ---


Dans la VM Gui sur AWS
	sudo apt install xrdp

Faut-il vraiment faire cela ? : sudo adduser xrdp ssl-cert  && sudo systemctl restart xrdp
https://linuxize.com/post/how-to-install-xrdp-on-ubuntu-20-04/


ssh -L 33389:localhost:3389 -l cloudus IPvmAWS



https://askubuntu.com/questions/1326143/local-ubuntu-desktop-cannot-login-after-logging-in-remotely-via-xrdp-session
Quand on met ça dans xrdp.ini, déjà je peux choisir ensuite une session et tenter un login mais ça marche jamais
[xrdp1-loggedin]
name=Local Active Session
lib=libvnc.so
username=na
password=ask
ip=127.0.0.1
port=5900


Test avec un nouvel user
sudo adduser seb



Tester aussi avec arrête session gnome de cloud us
https://askubuntu.com/questions/15795/how-can-you-log-out-via-the-terminal
Gnome-session-quit 
	==> ça fonctionne alors !! Il faut quand même utiliser l’ajout dans le xrdp.ni et il y a une première erreur normale, on sélectionne ensuite org avec cloud us et ensuite c’est bon on a une session gnome avec cloudus mais je suis pas certain de l’intérêt car il n’y a pas postman installé ni autre outils

