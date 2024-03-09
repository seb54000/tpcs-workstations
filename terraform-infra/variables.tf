variable "vm_number" {
  type = number
  default = 0
}

variable "cloudus_user_passwd" {
  type = string
}

variable "access_vm_enabled" {
  type = bool
  default = true
}

variable "docs_vm_enabled" {
  type = bool
  default = true
}

variable "token_gdrive" {
  type = string
  description = "token for gdrive API call in base64 format"
}

variable "tp_name" {
  type = string
  description = "tp type to chooose user_data (tpkube or tpiac)"
}

variable "tpiac_docs_file_list" {
  type = string
  default = <<EOF
  [
    "Consignes machine SSH TP iac",
    "TP IAC 2023 slides",
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