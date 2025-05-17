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
ansible-playbook -i inventory.aws_ec2.yml playbook.yml
```

@all:
  |--@ungrouped:
  |--@aws_ec2:
  |  |--access
  |--@role_access:
  |  |--access
  |--@role_docs:
  |  |--access
  |--@role_monitoring:
  |  |--access

