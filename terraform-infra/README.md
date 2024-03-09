# tpcs-workstations

[[_TOC_]]

curl -o tf.zip https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip tf.zip
rm tf.zip
sudo mv terraform /usr/local/bin/terraform


## How to create environement for TP

TF_VAR_vm_number is special, it corresponds to the number of sutdent you have in your group.

For the IaC TP (with API keys). This number is used so the accounts (API Key) are spread on the 7 european available regions (we keep Paris for the TP vms) in a round robin way. This means that if you jave more than 14 students (including trainer), you will have more than 2 accounts per region


You need to export vars, you can use a .env or export script
```bash
export TF_VAR_cloudus_user_passwd="xxxx"
export TF_VAR_vm_number=2
export TF_VAR_docs_vm_enabled=true     # webserver for publishing docs
export TF_VAR_access_vm_enabled=true   # Guacamole
export TF_VAR_tp_name="tpiac"   # Choose between tpiac and tpkube to load specific user_data

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
  - SCP `scp -i $(pwd)/key /var/tmp/my-file cloudus@docs.tpcs.multiseb.com:/var/www/html/`

Then simply terraform init/plan/apply and point your browser to the different URLs :

- http://access.tpcs.multiseb.com
- http://docs.tpcs.multiseb.com
- http://vmxx.tpcs.multiseb.com

ssh-keygen -f "/home/seb/.ssh/known_hosts" -R "docs.tpcs.multiseb.com"
ssh -i $(pwd)/key cloudus@docs.tpcs.multiseb.com

## Debug cloud Init or things that could go wrong

sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/user-data-common.log
sudo cat /var/log/user-data.log

Once I had this error in the /var/log/user-data.log for docs vm :

  - google.auth.exceptions.RefreshError: ('invalid_grant: Bad Request', {'error': 'invalid_grant', 'error_description': 'Bad Request'})
  - Using jwt.io website, I can see the token for google drive : "expiry": "2024-01-21T08:19:43.932962Z"
    - to read a JWT token through command line : https://gist.github.com/angelo-v/e0208a18d455e2e6ea3c40ad637aac53



## TODOs : 
- [x] manage serverinfo install or not (docs)
- [x] add files to server info - either google docs and list of the VMs
- [x] Manage var to decide if we provide tpkube or tpiac (download list is not the same, of course user_data are not the same)
  - [x] variablize the query parmaeter for python script to DL correct files  as a list of names
- [x] mutualize some part fo the cloud init for kube and serverinfo and tpiac -- use template to merge multiple files
  - [ ] review apt install and snap to put them in cloudinit instead of shell script
- [ ] guacamole - test SFTP and add to the readme to easily add new files in /var/www/html if we want to add files during the TP
- [x] docs VM : find a way to show the TP type (tpiac or tpkube)
- [x] solve annoying always tf change about nat_gateway : https://github.com/hashicorp/terraform-provider-aws/issues/5686
- [x] manage conditional in vm-docs.tf while tp_name is tpkube we won't have the AK/SK to publish so the templatefile for api_keyx may not work
- [x] migrate user_datas of guacamole, tpkube and tpiac like docs is managed
- [x] Add into in README or add a var in environement to manage the users.json file before provisioning (dependent of list of real users)
- [ ] Manage test the quotas on region if we need to split users for tpIAC (need to create a lot of VPC ...)
  - [ ] Add in vms.php a description of the region where the user is authorized
- [ ] Add a quotas.php to list actual and consumed quotas in each region
- [ ] Manage multi-region in users.json 
- [ ] Add let's encrypt certificate for guacamole (to move from HTTP to HTTPS) - or propose both possibility


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

