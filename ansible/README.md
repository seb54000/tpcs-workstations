# Ansible configuration

## Prerequisites

We gonna use a venv with ansible installed inside and tools for dynamic inventory

```bash
python3 -m venv .venv
source ".venv/bin/activate"
pip install --upgrade pip
pip install -r requirements.txt
ansible-galaxy collection install amazon.aws
ansible-inventory -i inventory.aws_ec2.yml --graph
```

@all:
  |--@ungrouped:
  |--@aws_ec2:
  |  |--vm00
  |  |--access_docs
  |--@tag_Name_vm00:
  |  |--vm00
  |--@tag_dns_record_cloudflare_dns_record_access____name:
  |  |--access_docs
  |--@tag_other_name_guacamole:
  |  |--access_docs
  |--@tag_Name_access_docs:
  |  |--access_docs


  TODO :
    add tags on all vms to group
    tag name = Roles : student, docs, access, monitoring, ...
    Value could be a list but then keyed groups should be done with a group per each value
    ie. ROles=docs, access
    gorups in inventory : ROles_docs , ROles_access, ...


TODO : create simple first playbook that just rint hostnames for each possible groups (hardcoded)

TODO : first task is to wait for success cloud-init finished
Add ssh key ref in inventory
And maybe simply do the copy of vms.php file
  Envisage to template it ? (to test usage of local env vars ?)