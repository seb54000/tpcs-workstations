variable "vm_number" {
  type = number
  default = 0
}

variable "cloudus_user_passwd" {
  type = string
}

variable "AccessDocs_vm_enabled" {
  type = bool
  default = true
}

variable "kube_multi_node" {
  type = bool
  default = false
}

variable "token_gdrive" {
  type = string
  description = "token for gdrive API call in base64 format"
}

variable "tp_name" {
  type = string
  description = "tp type to chooose user_data (tpkube or tpiac)"
}

variable "users_list" {
  type = string
}

variable "tpiac_docs_file_list" {
  type = string
  default = <<EOF
  [
    "Consignes machine SSH TP iac",
    "TP IAC 2024 slides",
    "TP IAC 2023 (version étudiant)"
  ]
EOF
}


variable "tpkube_docs_file_list" {
  type = string
  default = <<EOF
  [
    "INTRO slides 2023",
    "Docker slides 2023",
    "TP kubernetes 2023 (version étudiant)"
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
