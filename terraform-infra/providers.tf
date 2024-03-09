terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    ovh = {
      source  = "ovh/ovh"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "eu-west-3" # Paris
}

variable "ovh_endpoint" {
  type = string
  default = "ovh-eu"
}
variable "ovh_application_key" {
  type = string
}
variable "ovh_application_secret" {
  type = string
}
variable "ovh_consumer_key" {
  type = string
}

provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}