packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.4"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "= 1.1.6"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region where the platform VMs and resulting AMI are located."
  default     = "eu-west-3"
}

variable "source_ami" {
  type        = string
  description = "Existing Ubuntu 22.04 source image used by the student VMs."
  default     = "ami-01d21b7be69801c2f"
}

variable "build_instance_type" {
  type        = string
  description = "Temporary EC2 size used only while building the AMI."
  default     = "m5.large"
}

variable "subnet_id" {
  type        = string
  description = "Optional public subnet for the temporary Packer builder instance."
  default     = ""
}

variable "ami_name_prefix" {
  type        = string
  description = "Name prefix for the generated student AMI."
  default     = "tpcs-student-jammy"
}

source "amazon-ebs" "student" {
  region        = var.aws_region
  source_ami    = var.source_ami
  instance_type = var.build_instance_type
  ssh_username  = "ubuntu"
  subnet_id     = var.subnet_id == "" ? null : var.subnet_id

  ami_name        = "${var.ami_name_prefix}-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  ami_description = "TPCS student workstation packages built from the repository Ansible roles."
  force_deregister = false

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 32
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name       = "${var.ami_name_prefix}"
    ManagedBy  = "Packer"
    Repository = "tpcs-workstations"
    Role       = "student"
  }
}

build {
  name    = "tpcs-student"
  sources = ["source.amazon-ebs.student"]

  provisioner "ansible" {
    playbook_file       = "${path.root}/student-image.yml"
    inventory_directory = "${path.root}/.."
    groups              = ["role_student"]
    user                = "ubuntu"
    use_proxy           = false
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.root}/ansible.cfg",
      "ANSIBLE_ROLES_PATH=${path.root}/../roles",
      "ANSIBLE_FILTER_PLUGINS=${path.root}/../versions/filter_plugins",
      "ANSIBLE_HOST_KEY_CHECKING=False",
    ]
  }

  post-processor "manifest" {
    output = "${path.root}/../terraform-infra/.tpcs/packer-student-manifest.json"
  }
}
