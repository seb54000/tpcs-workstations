terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "eu-west-3" # Paris
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
variable "cloudflare_api_token" {
  type = string
}
variable "cloudflare_zone_id" {
  type = string
  default = "b8d7510b8514176bdc74e713579d1289"
}
