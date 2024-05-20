# tpcs-workstations

<!-- [[_TOC_]] -->

## How to create environement for TP

TF_VAR_vm_number is special, it corresponds to the number of student you have in your group.

For the IaC TP (with API keys). This number is used so the accounts (API Key) are spread on the 7 european available regions (we keep Paris for the TP vms) in a round robin way. This means that if you have more than 14 students (including trainer), you will have more than 2 accounts per region

TF_VAR_tp_name is also very important to correctly set up depending on which TP you are doing

You need to export vars, you can use a .env or export script
```bash
export TF_VAR_cloudus_user_passwd="xxxx"
export TF_VAR_vm_number=2
export TF_VAR_AccessDocs_vm_enabled=true   # Guacamole and docs (webserver for publishing docs with own DNS record)
export TF_VAR_tp_name="tpiac"   # Choose between tpiac and tpkube to load specific user_data
export TF_VAR_kube_multi_node=false # Add one (or more VM) to add a second node for Kube cluster

export AWS_ACCESS_KEY_ID=********************************
export AWS_SECRET_ACCESS_KEY=********************************
export AWS_DEFAULT_REGION=eu-west-3 # Paris
export TF_VAR_ovh_endpoint=ovh-eu
export TF_VAR_ovh_application_key=************
export TF_VAR_ovh_application_secret=************
export TF_VAR_ovh_consumer_key=************
export TF_VAR_token_gdrive="************"
```

:warning: IMPORTANT : Then you'll have to edit the cloudinit/users.json file to put the name of the students to affect them a vm number and a user that will be available through the docs vm.

:warning: IMPORTANT : Review the list of files you want to be downloaded from Gdrive and become available on the docs servers
- It is at the end of the variables.tf file - look for `tpiac_docs_file_list` and `tpkube_docs_file_list`

:warning: the oauth google API flow is just a nightmare and is not functioning anymore (expiry date is always a few minutes...)

Need to upload the files manually for the moment, much more quicker on a machine where the FUSE gdrive is mounted :

  - Copy the files from FUSE gdrive to a temporary local dir
    - or open a shell from the FUSE gdrive folder (in nautilus explorer, right click)
  - SCP :
    - `ssh -i $(pwd)/key cloudus@docs.tpcs.multiseb.com 'chmod 777 /var/www/html'`
    - `scp -i $(pwd)/key /var/tmp/my-file cloudus@docs.tpcs.multiseb.com:/var/www/html/`
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
ssh -i $(pwd)/key cloudus@docs.tpcs.multiseb.com

:warning: IMPORTANT : go to the docs vm and look at the quotas.php page and take a "screenshot" to know the actual quotas at the begining of the TP, we should have the same usage at the end

## Debug cloud Init or things that could go wrong

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

### Unactivated regions

You may have for instance with eu-central-2 and eu-south-2 an eeror with aws cli or terraform like `An error occurred (AuthFailure) when calling the DescribeInstances operation: AWS was not able to validate the provided access credentials`

This may be because the region is not activated, please verify wiht the root account and if needed enable them (but it could take up to 4 hour to be enabled, you may also comment in the variables the regions that pose problem and recreate the VMs)


## Simple shell checks

### Simple test to validate everything is up and running

```bash
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'hostname'
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'cat /home/ubuntu/user_data_student_finished && echo "cloudinit finished" || echo "cloudinit still ongoing"'
done

```



### Add microk8s additional nodes

VMs have to be created for the additional nodes (see `TF_VAR_kube_multi_node`)

```bash
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  JOIN_URL=$(ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'microk8s add-node --format json | jq -r .urls[0]')
  echo $JOIN_URL;
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@knode${digits}.tpcs.multiseb.com "microk8s join ${JOIN_URL} --worker"
  # ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@k2node${digits}.tpcs.multiseb.com "microk8s join ${JOIN_URL} --worker"
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com "kubectl get no"
done



for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com "kubectl get no"
  echo ""
done
```

### Check if regions are equally distributed for api key and working (mainly for TP IaC)

```bash
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'cat tpcs-iac/.env | grep REGION'
  REGION=$(ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'cat tpcs-iac/.env | grep REGION')
  echo $REGION | awk -F= '{ print $NF }'
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com aws ec2 describe-instances
done
```

### Quotas checks

- see in terraform dir `cloudinit/check_quotas.sh`

Take a footrpint at the begining of the TP, and do a diff at the end

```bash
LOGFILE="/var/tmp/aws-quota-checker-$(date +%Y%m%d-%H%M%S)"
for region in eu-central-1 eu-west-1 eu-west-2 eu-west-3 eu-south-1 eu-south-2 eu-north-1 eu-central-2
do
  sudo docker run -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${region} ghcr.io/brennerm/aws-quota-checker check all | grep -v 0/ | tee -a $LOGFILE
done
sort $LOGFILE | uniq | tee ${LOGFILE}.uniq
# rm /var/tmp/aws-quota-checker-*
```


### Useful how to resize root FS

Resize root FS magic : https://stackoverflow.com/questions/69741113/increase-the-root-volume-hard-disk-of-ec2-linux-running-instance-without-resta

```bash
for ((i=0; i<$TF_VAR_vm_number; i++))
do
  digits=$(printf "%02d" $i)
  echo "VM : vm0${i}"
  ssh-keygen -f "$(ls ~/.ssh/known_hosts)" -R "vm${digits}.tpcs.multiseb.com" 2&> /dev/null
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'sudo growpart /dev/xvda 1'
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'sudo resize2fs /dev/xvda1'
  ssh -o StrictHostKeyChecking=no -i $(pwd)/key cloudus@vm${digits}.tpcs.multiseb.com 'df -h /'
done
```

### TODO debig configured registry for micoro k8s
Info to put in support
  HOw to see configured registry / authorized for micork8s
cloudus@vm00:~$ cat /var/snap/microk8s/current/args/certs.d/docker.io/hosts.toml
server = "https://docker.io"

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]



### Prometheus preparation
# Create persistent volume for your data
docker volume create prometheus-data
# Start Prometheus container
docker run \
    -p 9090:9090 \
    -v /path/to/prometheus.yml:/etc/prometheus/prometheus.yml \
    -v prometheus-data:/prometheus \
    prom/prometheus



Pb with multi node, add node selector to avoid problem for ingress controller for the moment
https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/
nodeSelector :
  node.kubernetes.io/microk8s-controlplane: microk8s-controlplane

k logs -n ingress nginx-ingress-microk8s-controller-lpbnh
-------------------------------------------------------------------------------
NGINX Ingress controller
  Release:       v1.8.0
  Build:         35f5082ee7f211555aaff431d7c4423c17f8ce9e
  Repository:    https://github.com/kubernetes/ingress-nginx
  nginx version: nginx/1.21.6

-------------------------------------------------------------------------------

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

- [ ] Document how to connect to AWS console for users during tp IaC. (they have AK/SK access to configure terraform but cannot login to console : https://tpiac.signin.aws.amazon.com/console/)

- [ ] guacamole - test SFTP and add to the readme to easily add new files in /var/www/html if we want to add files during the TP
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
- [ ] Restrict more the permissions on ec2, vpc, ... and write a script to list all the remaining resources that can last after tpiac
- [ ] Envisage only one setup for the student VM including tpiac and tpkube prereqs (will be needed for IaC extension on Kube).
  - [ ] Should we clone both git repo (iac and kube) ?
  - [ ] Should we shut down / stop Kube cluster to save resources ?
- [ ] Envisage to add nodes for microk8s cluster as an option (while doing tpkube) - need to validate we can have 2 times vm.number as quotas
  - [ ] Envisage a third node and a ceph / rook cluster deployed on kube (local storage is not supported on multi-node by microk8s) https://microk8s.io/docs/addon-rook-ceph
    - [ ] Use micro cloud ?
  - [ ] Manage script in cloudinit to join cluster (need to get the access to the master, wait for join URL then join, to be don etigher from master or nodes)
- [ ] Deploy prometheus node exporter on all hosts and a prometheus on docs or access node to follow CPU/RAM usage
  - Prepare 2 or 3 queries to visualize that within prometheus (no grafana needed)
  - Do we need ansible at some point in time to deploy stuff after deployment ?
- [ ] :warning: ! restart automatically docker compose at startup for guacamole (otherwise after reboot (2nd day) the guacamole is not working anymore) - to be doubled check as docker compose seem to be relaunched

### Already done (kind of changelog)

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

## VMs provisioning and AK/SK overview

![overview.excalidraw.png](overview.excalidraw.png?raw=true "overview.excalidraw.png")

