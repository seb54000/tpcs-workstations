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