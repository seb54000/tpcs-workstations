

curl -o tf.zip https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip tf.zip
rm tf.zip
sudo mv terraform /usr/local/bin/terraform


TODO : 
- [x] manage serverinfo install or not (docs)
- [x] add files to server info - either google docs and list of the VMs
- [x] Manage var to decide if we provide tpkube or tpiac (download list is not the same, of course user_data are not the same)
  - [] still to manage fo DL list (ok for user_data)
- [] mutualize some part fo the cloud init for kube and serverinfo and tpiac -- use template to merge multiple files
- [] guacamole - test SFTP and add to the readme to easily add new files in /var/www/html if we want to add files during the TP
- [x] docs VM : find a way to show the TP type (tpiac or tpkube)
- [] solve annoying always tf change about nat_gateway : https://github.com/hashicorp/terraform-provider-aws/issues/5686
- [] manage conditional in vm-docs.tf while tp_name is tpkube we won't have the AK/SK to publish so the templatefile for api_keyx may not work
- [] migrate user_datas of guacamole, tpkube and tpiac like docs is managed


TODO on the VM that will execute the code
- pip install --upgrade google-api-python-client google-auth-httplib2 google-auth-oauthlib

TODO : variablize the query parmaeter for python script to DL correct files
  as a list of names

TODO var : to choose TP kube or TP iac and choose the correct user_data


access.tpcs.multiseb.com
docs.tpcs.multiseb.com
vmxx.tpcs.multiseb.com

tpcs = tp centrale-supelec
rename repo - tpcs-infra


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
  - create and carefully download the json file (you can save it in the keepass, it is a secret file)

Now you need to execute once a few lines of python (directly from a python3 CLI) on an existing machine to retreive the token file (which will be very sensitive and would be for sure stored in the keepass) - just adpat the following code with the path of the previously client_secret downloaded file

```bash
# pip install --upgrade google-api-python-client google-auth-httplib2 google-auth-oauthlib

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
client_secret = "/home/xxx/client_secret.json"
token_file = "/home/xxx/token.json"
SCOPES = ["https://www.googleapis.com/auth/drive"]
flow = InstalledAppFlow.from_client_secrets_file(
          client_secret, SCOPES
      )
creds = flow.run_local_server(port=0)
with open(token_file, "w") as token:
    token.write(creds.to_json())
```

You will use token.json file in the application code and that is the only thing you need to download files and interact with the API. :warning: this token file give access to the API without needing any other credentials.


Cloudinit order reference :
https://stackoverflow.com/questions/34095839/cloud-init-what-is-the-execution-order-of-cloud-config-directives

