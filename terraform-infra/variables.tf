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