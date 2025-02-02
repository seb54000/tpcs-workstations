# tpcs-workstations

<!-- [[_TOC_]] -->

## How to create environement for TP

TF_VAR_users_list is very important, it is the lit of student you have in your group. (and will be used to know how many vms you will provision : TF_VAR_vm_number)


For the IaC TP (with API keys). This number is used so the accounts (API Key) are spread on the 7 european available regions (we keep Paris for the TP vms) in a round robin way. This means that if you have more than 14 students (including trainer), you will have more than 2 accounts per region

TF_VAR_tp_name is also very important to correctly set up depending on which TP you are doing

You need to export vars, you can use a .env or export script
```bash
export TF_VAR_users_list='{
  "iac00": {"name": "John Doe"},
  "iac01": {"name": "Alice Doe"}
}'
export TF_VAR_vm_number=$(echo ${TF_VAR_users_list} | jq length)
export TF_VAR_monitoring_user="**********" #password will be the same to simplify
export TF_VAR_AccessDocs_vm_enabled=true   # Guacamole and docs (webserver for publishing docs with own DNS record)
export TF_VAR_tp_name="tpiac"   # Choose between tpiac and tpkube to load specific user_data
export TF_VAR_kube_multi_node=false # Add one (or more VM) to add a second node for Kube cluster
export TF_VAR_tpcsws_branch_name=master # This is used for which branch of tpcs-workstation git repo to target in scripts

export AWS_ACCESS_KEY_ID=********************************
export AWS_SECRET_ACCESS_KEY=********************************
export AWS_DEFAULT_REGION=eu-west-3 # Paris
export TF_VAR_ovh_endpoint=ovh-eu
export TF_VAR_ovh_application_key=************
export TF_VAR_ovh_application_secret=************
export TF_VAR_ovh_consumer_key=************
export TF_VAR_token_gdrive="************"
```

:warning: IMPORTANT : Review the list of files you want to be downloaded from Gdrive and become available on the docs servers
- It is at the end of the variables.tf file - look for `tpiac_docs_file_list` and `tpkube_docs_file_list`
- IMPORTANT : the files need to be in pdf format (otherwise the gdrive query won't find them)

:warning: the oauth google API flow is just a nightmare and is not functioning anymore (expiry date is always a few minutes...)

Need to upload the files manually for the moment, much more quicker on a machine where the FUSE gdrive is mounted :

  - Copy the files from FUSE gdrive to a temporary local dir
    - or open a shell from the FUSE gdrive folder (in nautilus explorer, right click)
  - SCP :
    - `ssh -i $(pwd)/key access@docs.tpcs.multiseb.com 'chmod 777 /var/www/html'`
    - `scp -i $(pwd)/key /var/tmp/my-file access@docs.tpcs.multiseb.com:/var/www/html/`
Then simply terraform init/plan/apply and point your browser to the different URLs :

In case you need to install terraform
```bash
curl -o tf.zip https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip tf.zip && rm tf.zip
sudo mv terraform /usr/local/bin/terraform
```

- http://access.tpcs.multiseb.com
- http://docs.tpcs.multiseb.com
- http://vmxx.tpcs.multiseb.com

ssh-keygen -f "/home/seb/.ssh/known_hosts" -R "docs.tpcs.multiseb.com"
ssh -i $(pwd)/key access@docs.tpcs.multiseb.com

:warning: IMPORTANT : go to the docs vm and look at the quotas.php page and take a "screenshot" to know the actual quotas at the begining of the TP, we should have the same usage at the end

## VMs provisioning and AK/SK overview

![overview.excalidraw.png](overview.excalidraw.png?raw=true "overview.excalidraw.png")

## Debug cloud Init or things that could go wrong

sudo cloud-init status --long
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/user-data-common.log
sudo cat /var/log/user-data.log

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
alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "terraform destroy in vm${digits} :"
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com "terraform -chdir=/home/vm${digits}/tpcs-iac/terraform/ destroy -auto-approve" | tee -a /var/tmp/tfdestroy-vm${digits}-$(date +%Y%m%d-%H%M%S)
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com "source /home/vm${digits}/tpcs-iac/.env && terraform -chdir=/home/vm${digits}/tpcs-iac/vikunja/terraform/ destroy -auto-approve" | tee -a /var/tmp/tfdestroy-vm${digits}-$(date +%Y%m%d-%H%M%S)
done

grep -e destroyed -e vm /var/tmp/tfdestroy-vm*
```

### Useful how to resize root FS

Resize root FS magic : https://stackoverflow.com/questions/69741113/increase-the-root-volume-hard-disk-of-ec2-linux-running-instance-without-resta

```bash
alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  # ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com 'sudo growpart /dev/xvda 1'
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com 'sudo resize2fs /dev/xvda1'
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com 'df -h /'
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

curl https://vm00.tpcs.multiseb.com/

# Double check the API URL should be something like vm00.tpcs.multiseb.com/api (as there is a kubernetes ingress listening on path /api forwarging to api service on port 3456 but you don't need port)

# Also check in kube file (vikunja.kube.complete.yml) :
#           - name: VIKUNJA_API_URL
#             value: vm00.tpcs.multiseb.com/api
# And also the VIkunja install URL should be vm00.tpcs.multiseb.com/api/v1

```


## Monitoring the platform

A prometheus and Grafana docker instances are installed on monitoring (which is actually shared with access and docs)

- You can acces grafana through https://monitoring.tpcs.multiseb.com (or also https://grafana.tpcs.multiseb.com) - admin username is monitoring (you have to guess the password)
- Prometheus can be reached https://prometheus.tpcs.multiseb.com

## Add microk8s additional nodes (work in progress)

VMs have to be created for the additional nodes (see `TF_VAR_kube_multi_node`)

```bash
alias ssh-quiet='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  # ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  JOIN_URL=$(ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com 'microk8s add-node --format json | jq -r .urls[0]')
  echo $JOIN_URL;
  ssh-quiet -i $(pwd)/key vm${digits}@knode${digits}.tpcs.multiseb.com "microk8s join ${JOIN_URL} --worker"
  # ssh-quiet -i $(pwd)/key vm${digits}@k2node${digits}.tpcs.multiseb.com "microk8s join ${JOIN_URL} --worker"
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com "kubectl get no"
done



for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  # ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  ssh-quiet -i $(pwd)/key vm${digits}@vm${digits}.tpcs.multiseb.com "kubectl get no"
  echo ""
done
```

### TODO debug configured registry for micoro k8s
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
 - host: vm00.tpcs.multiseb.com
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

- [ ] Envisage to stop microk8s during tp IaC (and envisage more powerful VMs for tpkube ??)
- [ ] Envisage only one setup for the student VM including tpiac and tpkube prereqs (will be needed for IaC extension on Kube - or maybe we will use an AWS kubernetes cluster only for TPiAC extension ??).
  - [ ] Should we clone both git repo (iac and kube) ?
  - [ ] Should we shut down / stop Kube cluster to save resources ?

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
- [ ] Add links to access, monitoring and other useful infos in docs webserver
- [ ] Envisage to launch ansible to finalize access/docs config if many write_files ? (already at the limit as we use wget on raw git files for dashboards, not merge to main proof by the way)


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



