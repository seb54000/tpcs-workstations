# tpcs-workstations

<!-- [[_TOC_]] -->

## How to create environement for TP

### PREREQUISITE : source bash variables ###
You need to export vars, you can use a .env or export script wherever you want (do not forget to source it before launching terraform or other scripts).

TF_VAR_users_list is very important, it is the list of student you have in your group. (and will be used to know how many vms you will provision : TF_VAR_vm_number)


For the IaC TP (with API keys). This number is used so the accounts (API Key) are spread on the 7 european available regions (we keep Paris for the TP vms) in a round robin way. This means that if you have more than 14 students (including trainer), you will have more than 2 accounts per region

TF_VAR_tp_name is also very important to correctly set up depending on which TP you are doing

```bash
export TF_VAR_users_list='{
  "vm00": {"name": "John Doe"},
  "vm01": {"name": "Alice Doe"}
}'
export TF_VAR_vm_number=$(echo ${TF_VAR_users_list} | jq length)
export TF_VAR_monitoring_user="**********" #password will be the same to simplify
export TF_VAR_AccessDocs_vm_enabled=true   # Guacamole and docs (webserver for publishing docs with own DNS record)
export TF_VAR_tp_name="tpiac"   # Choose between tpiac, tpkube or tpmon to load specific user_data
export TF_VAR_kube_multi_node=false # Add one (or more VM) to add a second node for Kube cluster
export TF_VAR_acme_certificates_enable=false # As Let's encrypt ACME Protocol has limits : https://letsencrypt.org/docs/rate-limits/#new-certificates-per-registered-domain  # You can visit this website to see las certificates https://crt.sh/?q=%25.tpcsonline.org&identity=%25.tpcsonline.org&deduplicate=Y # Or curl 'https://crt.sh/?q=%25.tpcsonline.org&output=json' to automate with jq
export TF_VAR_dns_subdomain="seb.tpcsonline.org" # You shoud only use tpcsonline.org when you're doing class
export TF_VAR_cloudflare_api_token=************

export AWS_ACCESS_KEY_ID=********************************
export AWS_SECRET_ACCESS_KEY=********************************
export AWS_DEFAULT_REGION=eu-west-3 # Paris
export TOKEN_GDRIVE="************"
export COPY_FROM_GDRIVE=false # Decide if copy of TP documents on docs vm will be done automatically (but for that, you need to have a valid token_gdrive and access to Gdrive)
```
### PREREQUISITE : install terraform ###
In case you need to install terraform
```bash
curl -o tf.zip https://releases.hashicorp.com/terraform/1.11.2/terraform_1.11.2_linux_amd64.zip
unzip tf.zip && rm tf.zip
sudo mv terraform /usr/local/bin/terraform
```


### PREREQUISITE : generate SSH keys ###
Generate an RSA keys pair and copy it in terraform-infra directory with generic names key and key.pub:
```bash
 ssh-keygen -t rsa -b 4096 # You can choose a different algorithm than rsa
 cp $HOME/.ssh/id_rsa.pub ./terraform-infra/key.pub
 cp $HOME/.ssh/id_rsa ../terraform-infra/key
```
- http://access.tpcsonline.org
- http://docs.tpcsonline.org
- http://vmxx.tpcsonline.org

### PREREQUISITE : install Ansible ###
```bash
sudo apt install -y python3-pip
sudo apt install -y python3.12-venv
python3 -m venv $HOME/ansiblevenv
source $HOME/ansiblevenv/bin/activate
pip install --upgrade pip
pip install -r requirements
ansible-galaxy collection install community.aws community.general # For snap module
ansible-inventory --graph
```
## DEPLOY INSTANCES
```bash
cd terraform_infra
terraform init
time terraform apply
cd ..
time ansible-playbook post_install.yml
```

Estimated duration for 10 vms
  Terraform :
  Ansible :

:warning: IMPORTANT : Review the list of files you want to be downloaded from Gdrive and become available on the docs servers
- It is at the end of the variables.tf file - look for `tpiac_docs_file_list`, `tpmon_docs_file_list` and `tpkube_docs_file_list`
- IMPORTANT : the files to have the exact name and be of type docs or slides (otherwise the gdrive query won't find them)
  - The script will automatically export current version in PDF format (from the google document last version)

:warning: the oauth google API flow is just a nightmare and is not functioning anymore (expiry date is always a few minutes...)

Need to upload the files manually for the moment, much more quicker on a machine where the FUSE gdrive is mounted :

  - Copy the files from FUSE gdrive to a temporary local dir
    - or open a shell from the FUSE gdrive folder (in nautilus explorer, right click)
  - SCP :
    - `ssh -i $(pwd)/key access@docs.tpcsonline.org 'chmod 777 /var/www/html'`
    - `scp -i $(pwd)/key /var/tmp/my-file access@docs.tpcsonline.org:/var/www/html/`




ssh-keygen -f "$HOME/.ssh/known_hosts" -R "docs.tpcsonline.org"
ssh -i $(pwd)/key access@docs.tpcsonline.org

:warning: IMPORTANT : go to the docs vm and look at the quotas.php page and take a "screenshot" to know the actual quotas at the begining of the TP, we should have the same usage at the end

Change guacadmin password in the web interface : Connect to the guacamole web interface : http://access.tpcsonline.org with guacadmin user and same password.
Click on your user at the top right of the Screen. Then "Paramètre", "Préférences" and you'll find a section to change your password

## VMs provisioning and AK/SK overview

![overview.excalidraw.png](overview.excalidraw.png?raw=true "overview.excalidraw.png")



## Debug cloud Init or things that could go wrong
```bash
sudo cloud-init status --long
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/user-data-common.log
sudo cat /var/log/user-data.log
```
Once I had this error in the /var/log/user-data.log for docs vm :

  - google.auth.exceptions.RefreshError: ('invalid_grant: Bad Request', {'error': 'invalid_grant', 'error_description': 'Bad Request'})
  - Using jwt.io website, I can see the token for google drive : "expiry": "2024-01-21T08:19:43.932962Z"
    - to read a JWT token through command line : https://gist.github.com/angelo-v/e0208a18d455e2e6ea3c40ad637aac53

### Guacamole problem

RDP connection on one VM is not working :

- If needed you can log with guacadmin user through console

working with guacadmin but not as user00
need to look at logs

On access (guacamole) VM

`cd guacamole-docker-compose/`
`docker compose ps`
`docker compose logs guacd`

### Unactivated regions

You may have for instance with eu-central-2 and eu-south-2 an eeror with aws cli or terraform like `An error occurred (AuthFailure) when calling the DescribeInstances operation: AWS was not able to validate the provided access credentials`

This may be because the region is not activated, please verify wiht the root account and if needed enable them (but it could take up to 4 hour to be enabled, you may also comment in the variables the regions that pose problem and recreate the VMs)


## Simple shell checks

alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'

### Students VMs and Access and docs VMs readiness (cloud init is successfuly ended)

```bash
terraform-infra/scripts/01_check_vms_readiness.sh
```
<!-- TODO  --> Check docs machine is reachable (just do a curl ?) , same for access , check that all the dos in the list are there on the nginx page ?


### Check if regions are equally distributed for api key and working (mainly for TP IaC)

```bash
terraform-infra/scripts/02_check_region_distribution_and_instances.sh
```

### Check if default VPC exists on user's regions and with default subnet

```bash
terraform-infra/scripts/03_check_region_default_subnets_and_gw.sh
```

### Quotas checks

- see in terraform dir `cloudinit/check_quotas.sh`

Take a footprint at the begining of the TP, and do a diff at the end

```bash
./scripts/04_quotas_snapshot.sh

# rm /var/tmp/aws-quota-checker-*
# grep costly ressources
LOGFILE="/var/tmp/aws-quota-checker-$(date +%Y%m%d"
grep -e loadbalancer -e instance -e running ${LOGFILE}*.uniq | grep -v 'AWS profile: default'

```

### TP IaC - force terraform destroy in the end for all VMs

```bash
./scripts/08_tpiac_terraform_destroy_everywhere.sh
```

### Useful how to resize root FS

Resize root FS magic : https://stackoverflow.com/questions/69741113/increase-the-root-volume-hard-disk-of-ec2-linux-running-instance-without-resta

```bash
alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  # ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcsonline.org" 2&> /dev/null
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org 'sudo growpart /dev/xvda 1'
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org 'sudo resize2fs /dev/xvda1'
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcsonline.org 'df -h /'
done
```

### Quick TP kube test

Build the docker images locally (on vm00 - vmxx)

```bash
cd ~/tp-cs-containers-student/docker/vikunja/complete
docker build --tag localhost:32000/front:v2 -f frontend.Dockerfile .
docker push localhost:32000/front:v2
docker build --tag localhost:32000/api:v1 -f api.Dockerfile .
docker push localhost:32000/api:v1

cd ~/tp-cs-containers-student/kubernetes/vikunja
kubectl apply -f vikunja.kube.complete.yml
kubectl get po

curl https://vm00.tpcsonline.org/

# Double check the API URL should be something like vm00.tpcsonline.org/api (as there is a kubernetes ingress listening on path /api forwarging to api service on port 3456 but you don't need port)

# Also check in kube file (vikunja.kube.complete.yml) :
#           - name: VIKUNJA_API_URL
#             value: vm00.tpcsonline.org/api
# And also the VIkunja install URL should be vm00.tpcsonline.org/api/v1

```


## Monitoring the platform

A prometheus and Grafana docker instances are installed on monitoring (which is actually shared with access and docs)

- You can acces grafana through https://monitoring.tpcsonline.org (or also https://grafana.tpcsonline.org) - admin username is the value of TF_VAR_monitoring_user (you have to guess the password)
- Prometheus can be reached https://prometheus.tpcsonline.org

## Add microk8s additional nodes (work in progress)

VMs have to create the additional nodes (see `TF_VAR_kube_multi_node`)

Need to change the above var and relaunch terraform. After cloud init is finished, we need to join the nodes.

WARNING : not yet working

```bash
terraform-infra/scripts/scripts/05_check_knodes.sh
# Wiat for finished cloud-init
terraform-infra/scripts/scripts/06_join_microk8S_nodes.sh
```

If you want to monitor the additional nodes in Prometheus, you will have to deit directly the file on the access vm

```bash
sudo vi /var/tmp/prometheus.yml
        - knode00.tpcsonline.org:9100

docker-compose -f monitoring_docker_compose.yml restart
```

### TODO debug configured registry for micro k8s
Info to put in support
  HOw to see configured registry / authorized for micork8s
vm00@vm00:~$ cat /var/snap/microk8s/current/args/certs.d/docker.io/hosts.toml
server = "https://docker.io"

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]




Pb with multi node, add node selector to avoid problem for ingress controller for the moment
https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/
nodeSelector :
  node.kubernetes.io/microk8s-controlplane: microk8s-controlplane

k logs -n ingress nginx-ingress-microk8s-controller-lpbnh

NGINX Ingress controller
  Release:       v1.8.0
  Build:         35f5082ee7f211555aaff431d7c4423c17f8ce9e
  Repository:    https://github.com/kubernetes/ingress-nginx
  nginx version: nginx/1.21.6



W0404 11:57:09.206186       7 client_config.go:618] Neither --kubeconfig nor --master was specified.  Using the inClusterConfig.  This might not work.
I0404 11:57:09.206461       7 main.go:209] "Creating API client" host="https://10.152.183.1:443"



TODO a ajouter dans le TP

k exec -it -n ingress nginx-ingress-microk8s-controller-k4hgg cat /etc/nginx/nginx.conf | grep -A 20  "## start server vm"





à ajouter dans bgd.rollout.yml - to make the demo for progressive deployment from within the desktop


apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bgd
  labels:
    name: bgd
spec:
 rules:
 - host: vm00.tpcsonline.org
   http:
     paths:
     - pathType: Prefix
       path: "/"
       backend:
         service:
           name: bgd
           port:
             number: 8080



## TODOs :

- [ ] Need to check that dns_subdomain var is really working with grafana dahsboards : terraform-infra/cloudinit/monitoring_grafana_node_full_dashboard.json
- [ ] Remove VScode extension like kube when not installed (top monitoring ?)
- [ ] TODO add jinja if custom_files is not empty (cloud-config.yaml.tftpl) -- for knode otherwise cloud-inint error
- [ ] Envisage only one setup for the student VM including tpiac and tpkube prereqs (will be needed for IaC extension on Kube - or maybe we will use an AWS kubernetes cluster only for TPiAC extension ??).
  - [ ] Should we clone both git repo (iac and kube) ?
  - [X] Should we shut down / stop Kube cluster to save resources ? - maybe only go for c5.xlarge VMs

- [ ] Envisage to add nodes for microk8s cluster as an option (while doing tpkube) - need to validate we can have 2 times vm.number as quotas
  - [ ] Envisage a third node and a ceph / rook cluster deployed on kube (local storage is not supported on multi-node by microk8s) https://microk8s.io/docs/addon-rook-ceph
    - [ ] Use micro cloud ?
  - [ ] Manage script in cloudinit to join cluster (need to get the access to the master, wait for join URL then join, to be done later from master or nodes)

- [ ] Add a quotas.php to list actual and consumed quotas in each region (interesting at the begining of the TP and in the end to take "screenshot")
  - [ ] study usage of https://pypi.org/project/aws-quota-checker/ to do it outisde php webpage but maybe easier
    - aws cli doesn't show easily the current usage of quotas
    - need to loop on all european regions (checker llist only for one region)
    - `docker run -e AWS_ACCESS_KEY_ID=ABC -e AWS_SECRET_ACCESS_KEY=DEF -e AWS_DEFAULT_REGION=eu-central-1 ghcr.io/brennerm/aws-quota-checker check all`
    - add a grep -v on 0/ so you will remove all results that are not using any quotas
    - `docker run -e AWS_ACCESS_KEY_ID=ABC -e AWS_SECRET_ACCESS_KEY=DEF -e AWS_DEFAULT_REGION=eu-central-1 ghcr.io/brennerm/aws-quota-checker check all | grep -v 0/`
      - great !! need to loop through region, put everything in a file and remove full duplicate lines (for instance IAM file will be in every region)
      - work on a shell scripts that we can later add directly on one VM (like docs) and call through a cron each hour and generate html results we can later consult
        - see `cloudinit/check_quotas.sh`
- [ ] Ability to launch checking scripts from the docs vm through PHP (or as a cron and consult in web browser)
    - beware that we will again reach the write_file cloud-init size limit (so we need to git checkout and choose the branch, maybe this could be part of variables)
- [ ] Restrict more the permissions on ec2, vpc, ... and write a script to list all the remaining resources that can last after tpiac
- [ ] Identify 2 or 3 queries to visualize in prometheus/grafana and note them here or put links in Readm (or even docs root webserver)
  - Disk space usage/available for monitoring
  - Memory available
- [ ] launch quotas script on a cronjob from access/docs/monitoring vms and expose prometheus metrics with results ?
  - If we do that, we need ot have a backup and not forget to have a snapshot before launching everything...
- [ ] Envisage to launch ansible to finalize access/docs config if many write_files ? (already at the limit as we use wget on raw git files for dashboards, not merge to main proof by the way)


### ANSIBLE
- [ ] remove unused terraform code instead of commenting (now that it is tested)
- [ ] Verify functional content of this PR is migrated https://github.com/seb54000/tpcs-workstations/pull/11/files
  - aws_prom_exporter.sh + part in the nginx conf file + prometheus config file to scrape
  - gdrive.py enhancement for removing hidden slides
  - [X] grafana dashobard : monitoring_grafana_aws_metrics.json
  - dirty fix in the guacamole image : in access user data
  - vms.php enhancement to mark in RED when IP and DNS are different
  - Script 07 quick fix
  - Adding a new script 08 (to destroy TF for students in TP IAC at the end)
  - fix in vars for token to work in terraform (maybe not necessary anymore)
- [ ] Manage tpmon bash script for monitoring TP option (currently not managed, only kube and iac are done). See cloudinit/user_data_tpmon.sh
- [ ] Test use cases such as changing some conf/vars and relaunch playbook
  - If you change the DNS_suffix, you may have to trash almost everything
  - What happen if you change some guacamole config
  - What happen if you change the type of tp (mon, iac, kube) ? We may want to remove everything and redo the clone and other bits of config (this a real use case as sometimes you see, you launched everything with a bad var and don't want to restart everything)
- [ ] Measure execution times and envisage to parralelize more (don't wait the students vms are ready to execute roles on docs/access)
  - We do not want a very fast execution but it should be reasonable (ie. around 10 minutes for first playbook run, then 1 to 3 minutes in case of a rerun/configuration change)
- [X] actual relaunch of playbooks lose the certbot/letsencrypt config and https is not working (as template overwrites the nginc config wilth only listening on port 80) -- envisage to use ansible certbot / crypot collections : https://docs.ansible.com/ansible/latest/collections/community/crypto/acme_certificate_module.html or https://github.com/geerlingguy/ansible-role-certbot  -- or simply only requires certificates and manage ourselves the nginx template
- [X] replace AMI ID image reference is not working : [student : Replace AMI ID in all terraform files]
- [X] Test with COPY_FROM_GDRIVE=true and TOKEN_GDRIVE bash variables
- [X] Fix problem on vm student with color (on first RDP access)
- [ ] Make separated roles for things related to the docs (nginx), to the access (guacamole) and to monitoring (grafana).
- [ ] Integrate terraform part in ansible playbook ??
- [ ] Finish converting bash scripts in ansible tasks (but is it really necessary ?)
- [ ] Adding tags to avoid reluanching all the playbook for a change on a specific part

### Already done (kind of changelog)

- [x] define vars in credentials setup or elsewhere with the branch name we want to target for grafana dashboards and other items we'd like to pick through raw format on github (instead of master hardcoded value in wget in script)
- [x] If we are in tpKube, do not display AWS console link and A/K colum in vms.php
- [x] Paris timezone + Layout keyboard (AZERTY) in guacamole, in RDP remmina
  - beware in remmina preferences, I had to switch default keyboard in RDP prefs to FR as by default it detects english I don't know why...
- [x] Set default browser in guacamole VM
  - through updating xfce default shortcut `/usr/share/applications/xfce4-web-browser.desktop`
- [x] guacamole - test SFTP and add to the readme to easily add new files in /var/www/html if we want to add files during the TP
  - SFTP is working but only on student's VMs (no X desktop on access/docs/monitoring), we can still easily use SCP (with SSH) to copy a file
- [x] Template default grafana user/pwd from env vars (instead of hardcoded in docker compsoe)
- [x] Change vm username with vmXX instead of cloudus ??
  - also align IAM usernames in AWS (we then use vm00, vm01 as aws users)
- [x] Deploy prometheus node exporter on all hosts and a prometheus on docs or access node to follow CPU/RAM usage
- [x] Why in guacamole VMs the code and other apps are not launched at first login anymore ? (cloud inti was blocked and not finished....)
- [x] Document how to connect to AWS console for users during tp IaC. (they have AK/SK access to configure terraform but cannot login to console : https://tpiac.signin.aws.amazon.com/console/)
- [x] Check why some files do not appear in docs (TP 2024) - maybe we didn't export the PDF ?? YES it is only PDF files
- [x] vm.php script should be launched every 5 minutes through cron and create a static html file (that will be displayed, otherwise it is much too long)
- [x] manage serverinfo install or not (docs)
- [x] add files to server info - either google docs and list of the VMs
- [x] Manage var to decide if we provide tpkube or tpiac (download list is not the same, of course user_data are not the same)
  - [x] variablize the query parmaeter for python script to DL correct files  as a list of names
- [x] mutualize some part fo the cloud init for kube and serverinfo and tpiac -- use template to merge multiple files
  - [x] review apt install and snap to put them in cloudinit instead of shell script
- [x] docs VM : find a way to show the TP type (tpiac or tpkube)
- [x] solve annoying always tf change about nat_gateway : https://github.com/hashicorp/terraform-provider-aws/issues/5686
- [x] manage conditional in vm-docs.tf while tp_name is tpkube we won't have the AK/SK to publish so the templatefile for api_keyx may not work
- [x] migrate user_datas of guacamole, tpkube and tpiac like docs is managed
- [x] Add into in README or add a var in environement to manage the users.json file before provisioning (dependent of list of real users)
- [x] Manage test the quotas on region if we need to split users for tpIAC (need to create a lot of VPC ...)
  - [x] Add in vms.php a description of the region where the user is authorized
  - [x] Manage a multi-region setup (with authorization for API key only on a specific region for a specific user) - used only in tpiac
- [x] Add root disk size to 16 Gb as 99% of space is occupied by default on a default 8 Gb disk
- [x] Add an excalidraw to show the students VMs and the tpiac regions with credentials files so we can easily understand what is usied for what and also the mechanism of round robin region associated with IAM group and policies
- [x] Shutdown VMs at 2am instead of 8.pm (so students can work in the evening)
- [x] Add K9s for dashboard in CLI mode for Kube (https://k9scli.io/)
- [x] Add let's encrypt certificate for guacamole (to move from HTTP to HTTPS) - or propose both possibility
    - [x] : need to add let's encrypt also for docs vm
- [x] Use same VM for docs and access (guacamole) while keeping DNS records
    - [x] refactor all var names and files to have access_docs
    - [x] debug assume role to VM not working for docs, unable to do aws CLI commands (bad credentials...)
      - https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html
- [x] Fix interact with gdrive in python (authentication problem)
    - https://medium.com/@matheodaly.md/create-a-google-cloud-platform-service-account-in-3-steps-7e92d8298800
    - https://medium.com/@matheodaly.md/using-google-drive-api-with-python-and-a-service-account-d6ae1f6456c2
- [X] Envisage to stop microk8s during tp IaC (and envisage more powerful VMs for tpkube ??)
- [X] Add links to access, monitoring and other useful infos in docs webserver
- [X] Export google documents in PDF (Do not need to already have them in PDF)
- [X] Do not create IAM tp_iac ressources for tpkube and tpmon (to save very little on AWS account)
- [X] Add acme_certificates_enable variable to choose if we want real ACME certificates or selfsigned (because when doing multiple create and destroy tests, we can block the certificates issuance as it is limited to a certain number)
- [X] Add a copy_from_gdrive var to decide if documents should be automatically copied form Gdrive to docs (needs grdive token)
- [X] Remove the vms with a status of terminated (removed) in the vms.php listing
- [X] Use a tpcsonline.org domain on Cloudflare more reliable than OVH
  - [X] add a dns_subdomain var to enable parralel working like access.xxx.tpcsonline.org
- [X] Add a script (07) to check certificates delivered in the last 7 days (to check letsencrypt limit)
- [X] Add a basic shell script prom exporter to follow aws instances (especially useful for TP IAC)
  - Use this kind of metric : count (aws_instance{state!="terminated"}) by (region)
- [X] Add a small checks in vms.html (php) to easily visualize that DNS record and EIP are not matching
- [X] Add a minimalist Grafana dashboard for metrics AWS prom exporter
- [X] Add a 08script to terraform destroy everything at the end of the TP IaC (to be double checked while running)

## API access settings to Gdrive (Google Drive)

https://developers.google.com/drive/api/quickstart/python

- Create a project (with account mapped to Gdrive) : https://console.cloud.google.com/cloud-resource-manager
  - name like : tpcs-get-files (no need to associate Zone/org)
- enaple API to gdrive for this project : https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com&hl=fr
- configure Oauth consent mamagement : https://console.cloud.google.com/apis/credentials/consent?hl=fr (for the project)
  - user type : external
  - app-name : tpcs-get-files ; email : provide valid email ; same for developer email (only those 3 fields are mandatory)
  - don't need to add scopes, you can continue
  - Add a test user with the email of the gdrive account you want to give access to and continue until final validation
- Create credential for a desktop app :  https://console.cloud.google.com/apis/credentials?hl=fr
  - Create credential and choose ID Oauth
  - type desktop app ; name : tpcs-get-files
  - create and carefully download the client_secret.json file (you can save it in the keepass, it is a secret file)

Now you need to execute once a few lines of python (directly from a python3 CLI) on an existing machine to retreive the token file (which will be very sensitive and would be for sure stored in the keepass) - just adapt the following code with the path of the previously client_secret downloaded file

```bash
# pip install --upgrade google-api-python-client google-auth-httplib2 google-auth-oauthlib

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
client_secret = "/var/tmp/client_secret.json"
token_file = "/var/tmp/token.json"
SCOPES = ["https://www.googleapis.com/auth/drive"]
flow = InstalledAppFlow.from_client_secrets_file(
          client_secret, SCOPES
      )
creds = flow.run_local_server(port=0)
with open(token_file, "w") as token:
    token.write(creds.to_json())
```

You will use token.json file in the application code and that is the only thing you need to download files and interact with the API. :warning: this token file give access to the API without needing any other credentials.
This token file has to be encoded in base64 then exported as a var for terraform use in the credential secret file : export TF_VAR_token_gdrive="************"

## Other tips and tricks

Cloudinit order reference :
https://stackoverflow.com/questions/34095839/cloud-init-what-is-the-execution-order-of-cloud-config-directives



