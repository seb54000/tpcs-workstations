variable "vm_number" {
  type    = number
  default = 0
}

variable "monitoring_user" {
  type        = string
  description = "username for grafana login"
}

variable "tpcsws_branch_name" {
  type        = string
  description = "branch of tpcs-workstations git repo"
}

variable "tpcsws_git_repo" {
  type        = string
  description = "github repo where this code is hosted. Used in case this git repo would be forked to get some raw files from vms"
  default     = "seb54000/tpcs-workstations"
}

variable "acme_certificates_enable" {
  type        = string
  description = "Enable or not certbot ACME certificates on nginx access docs"
}

variable "AccessDocs_vm_enabled" {
  type    = bool
  default = true
}

variable "copy_from_gdrive" {
  type        = bool
  default     = false
  description = "Decide if copy of TP documents on docs vm will be done automatically from Gdrive"
}

variable "kube_multi_node" {
  type    = bool
  default = false
}

variable "token_gdrive" {
  type        = string
  description = "token for gdrive API call in base64 format"
  default     = "ZmFrZXRva2VuCg==" # faketoken in base64 but should be in gzip format...
}

variable "dns_subdomain" {
  type        = string
  description = "You shoud only use tpcsonline.org when you're doing class"
}

variable "tp_name" {
  type        = string
  description = "tp type to choose user_data (tpkube or tpiac)"
}

variable "users_list" {
  type = string
}

variable "access_docs_flavor" {
  type    = string
  default = "t3.xlarge" # Guacamole needs RAM
}
variable "kube_node_vm_flavor" {
  type    = string
  default = "t3.medium"
}
variable "student_vm_flavor" {
  type = string
  # t3.medium = 2CPU/4Go RAM
  # default = "c5.xlarge" # 4CPU/8Go
  # default = "c5.large"  # 2CPU/4Go
  default = "m5.large" # 2CPU/8Go

}

variable "tpiac_docs_file_list" {
  type    = string
  default = <<EOF
  [
    "TP IAC 00 slides INTRO",
    "TP IAC 01 slides support cours",
    "TP IAC 02 (version étudiant)",
    "TP IAC 03 slides demande feedback"
  ]
EOF
}


variable "tpkube_docs_file_list" {
  type    = string
  default = <<EOF
  [
    "TP KUBE 00 slides INTRO",
    "TP KUBE 01 slides Docker support cours",
    "TP KUBE 02 Docker TP (version étudiant)",
    "TP KUBE 03 slides Kubernetes support cours",
    "TP KUBE 04 Kubernetes TP (version étudiant)",
    "TP KUBE 05 slides demande feedback"
  ]
EOF
}

variable "tpmon_docs_file_list" {
  type    = string
  default = <<EOF
  [
    "TP MON 00 slides INTRO",
    "TP MON 01 slides support cours",
    "TP MON 02 TP (version étudiant)",
    "TP MON 03 slides demande feedback"
  ]
EOF
}

variable "ami_for_template_with_regions_list" {
  type = list(string)
  default = [
    # List done with https://cloud-images.ubuntu.com/locator/ec2/ Noble 24.04 + amd64
    "ami-05d9d500849d3fece", #"eu-central-1",
    "ami-0b0087db031e71474", #"eu-west-1",
    "ami-0d3b447228dab952e", #"eu-west-2",
    "ami-061bdb40c12e7d8f1", #"eu-south-1",
    # "eu-west-3", //We keep Paris for guacamole VMs
    "ami-00a60eeae18abc601", #"eu-south-2",
    "ami-0dc1ddd4917dcf47a", #"eu-north-1",
    "ami-08946bcde99d2248b", #"eu-central-2"
  ]
}

variable "tpiac_regions_list_for_apikey" {
  type = list(string)
  default = [
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-south-1",
    # "eu-west-3", //We keep Paris for guacamole VMs
    "eu-south-2",
    "eu-north-1",
    "eu-central-2"
  ]
}

# Europe (Frankfurt)	eu-central-1
# Europe (Ireland)	eu-west-1
# Europe (London)	eu-west-2
# Europe (Milan)	eu-south-1
# Europe (Paris)	eu-west-3
# Europe (Spain)	eu-south-2
# Europe (Stockholm)	eu-north-1
# Europe (Zurich)	eu-central-2

# variable "student_names_list" {
#   type = list(object)
#   default = [
#     { "id" = "00", "name" = "Sebastien CLAUDE" },
#     { "id" = "01", "name" = "Jean DUPONT" }
#   ]
# }


# {
#     ${jsonencode({
#     %{ for id,name in student_names_list ~}
#     "iac${id}": {"name": "${name}"},
#     %{ endfor ~}
# }


# TODO template in terraform and usage of TF_var in .env with the names == for users.json.tftpl
# This way, we don't have to modify the json file, only the .env (need to be able to do a loop or verify if variables are empty)
# loop : with
# https://stackoverflow.com/questions/57561084/template-tf-and-user-data-yaml-tpl-loop-through-a-variable-of-type-list
