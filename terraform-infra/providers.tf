terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 4.67.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "= 2.4.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.4.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.25.0"
    }
  }

  required_version = "= 1.11.4"
}

provider "aws" {
  region              = "eu-west-3" # Paris
  allowed_account_ids = [var.tpcs_aws_account_id]
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
variable "cloudflare_api_token" {
  type = string
}
variable "cloudflare_zone_id" {
  type    = string
  default = "b8d7510b8514176bdc74e713579d1289"
}
