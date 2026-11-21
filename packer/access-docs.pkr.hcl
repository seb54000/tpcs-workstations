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
  type    = string
  default = "eu-west-3"
}

variable "source_ami" {
  type    = string
  default = "ami-01d21b7be69801c2f"
}

variable "build_instance_type" {
  type    = string
  default = "m5.large"
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "ami_name_prefix" {
  type    = string
  default = "tpcs-access-docs-jammy"
}

variable "image_generation" {
  type = string
}

source "amazon-ebs" "access_docs" {
  region        = var.aws_region
  source_ami    = var.source_ami
  instance_type = var.build_instance_type
  ssh_username  = "ubuntu"
  subnet_id     = var.subnet_id == "" ? null : var.subnet_id

  ami_name         = "${var.ami_name_prefix}-${var.image_generation}"
  ami_description  = "TPCS access/docs package layer; archive generation ${var.image_generation}."
  force_deregister = false

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name                = var.ami_name_prefix
    ManagedBy           = "Packer"
    Repository          = "tpcs-workstations"
    Role                = "access-docs"
    TPCSManaged         = "true"
    TPCSImageProfile    = "access-docs"
    TPCSImageGeneration = var.image_generation
    TPCSImageSource     = "Packer-candidate"
  }

  snapshot_tags = {
    ManagedBy           = "Packer"
    Repository          = "tpcs-workstations"
    TPCSManaged         = "true"
    TPCSImageProfile    = "access-docs"
    TPCSImageGeneration = var.image_generation
  }
}

build {
  name    = "tpcs-access-docs"
  sources = ["source.amazon-ebs.access_docs"]

  provisioner "ansible" {
    playbook_file       = "${path.root}/access-docs-image.yml"
    inventory_directory = "${path.root}/.."
    groups              = ["role_access"]
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
    output = "${path.root}/../terraform-infra/.tpcs/packer-access-docs-manifest.json"
  }
}
