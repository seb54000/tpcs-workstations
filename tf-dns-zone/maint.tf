terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    ovh = {
      source = "ovh/ovh"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}

provider "ovh" {
  endpoint           = "ovh-eu"
  # Rest of config is in env VARS
  # application_key    = "xxxxxxxxx"
  # application_secret = "yyyyyyyyy"
  # consumer_key       = "zzzzzzzzzzzzzz"
}

variable "vm_dns_record_suffix" {
  type = string
  default = "tpkube.multiseb.com"
}

resource "aws_route53_zone" "tpkube" {
  name = "${var.vm_dns_record_suffix}"
}

output "tpkube_zone_ns" {
  value = aws_route53_zone.tpkube.name_servers
}

resource "ovh_domain_zone_record" "tpkube" {
  zone      = "tpkube.multiseb.com"
  subdomain = "test"
  fieldtype = "A"
  ttl       = 3600
  target    = "0.0.0.0"
}