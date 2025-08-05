variable "vm_number" {
  type    = number
  default = 0
}

variable "monitoring_user" {
  type        = string
  description = "username for grafana login"
}

variable "acme_certificates_enable" {
  type = string
  description = "Enable or not certbot ACME certificates on nginx access docs"
}

variable "AccessDocs_vm_enabled" {
  type    = bool
  default = true
}


variable "kube_multi_node" {
  type    = bool
  default = false
}

variable "dns_subdomain" {
  type = string
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
  type = string
  default = "m5.large" # Guacamole needs RAM (previsously t3.xlarge)
}
variable "kube_node_vm_flavor" {
  type = string
  default = "t3.medium"
}
variable "student_vm_flavor" {
  type = string
  # t3.medium = 2CPU/4Go RAM
  # default = "c5.xlarge" # 4CPU/8Go
  # default = "c5.large"  # 2CPU/4Go
  default = "m5.large"  # 2CPU/8Go

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
