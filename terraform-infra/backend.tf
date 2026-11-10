terraform {
  # Address, credentials and locking are supplied by tf.sh through TF_HTTP_*.
  backend "http" {}
}

variable "tpcs_aws_account_id" {
  description = "AWS account verified by STS by the controller helper."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.tpcs_aws_account_id))
    error_message = "Run Terraform through tf.sh to select the AWS account and backend."
  }
}
