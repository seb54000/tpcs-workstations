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
  region  = "us-east-1"
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


resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_security_group" "guacamole" {
  name        = "guacamole"
  description = "Allow all inbound/outbound traffic"
  vpc_id      = aws_default_vpc.default.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    tpcentrale = "tpcentrale"
  }
}

# resource "aws_security_group_rule" "allow_all_ingress" {
#   type              = "ingress"
#   from_port        = 0
#   to_port          = 0
#   protocol         = "-1"
#   cidr_blocks      = ["0.0.0.0/0"]
#   ipv6_cidr_blocks = ["::/0"]
#   security_group_id = aws_security_group.guacamole.id
# }

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port        = 22
  to_port          = 22
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.guacamole.id
}

# resource "aws_security_group_rule" "http" {
#   type              = "ingress"
#   from_port        = 80
#   to_port          = 80
#   protocol         = "tcp"
#   cidr_blocks      = ["0.0.0.0/0"]
#   ipv6_cidr_blocks = ["::/0"]
#   security_group_id = aws_security_group.guacamole.id
# }

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port        = 443
  to_port          = 443
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.guacamole.id
}

resource "aws_security_group_rule" "guacamole" {
  type              = "ingress"
  from_port        = 8080
  to_port          = 8080
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.guacamole.id
}

resource "aws_key_pair" "tpkube_key" {
  key_name   = "guacamole_key"
  public_key = "${file("guacamole_key.pub")}"
}


variable "cloudus_user_passwd" {
  type = string
}

resource "ovh_domain_zone_record" "guacamole" {
  zone      = "multiseb.com"
  subdomain = "guacamole.tpiac"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.guacamole.public_ip
}

resource "ovh_domain_zone_record" "keycloak" {
  zone      = "multiseb.com"
  subdomain = "keycloak.tpiac"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.guacamole.public_ip
}

# variable "vm_dns_record_suffix" {
#   type = string
#   default = "tpkube.multiseb.com"
# }

# data "aws_route53_zone" "tpkube" {
#   name         = "${var.vm_dns_record_suffix}."
# }

# resource "aws_route53_record" "tpkube_vm" {
#   count   = var.vm_number
#   zone_id = data.aws_route53_zone.tpkube.zone_id
#   name    = "vm${count.index}.${var.vm_dns_record_suffix}"
#   type    = "A"
#   ttl     = "60"
#   records = [aws_instance.tpkube-instance[count.index].public_ip]
# }


# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are not TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "user_data" {
      template = file("user_data.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        hostname_new = "${format("guacamole")}"
      }
}

resource "aws_instance" "guacamole" {
  ami             = "ami-004dac467bb041dc7"   # us-east-1 : Ubuntu 22.04 LTS Jammy jellifish
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.guacamole.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 20 # in GB
  }

  lifecycle {
    ignore_changes = [ user_data]
  }

  tags = {
    Name = "guacamole-keycloak"
  }

}

output "guacamole_ip" {
  value = aws_instance.guacamole[*].public_ip
}

