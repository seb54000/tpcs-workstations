terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}



resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_security_group" "tpkube_secgroup" {
  name        = "tpkube_secgroup"
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
#   security_group_id = aws_security_group.tpkube_secgroup.id
# }

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port        = 22
  to_port          = 22
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

# resource "aws_security_group_rule" "http" {
#   type              = "ingress"
#   from_port        = 80
#   to_port          = 80
#   protocol         = "tcp"
#   cidr_blocks      = ["0.0.0.0/0"]
#   ipv6_cidr_blocks = ["::/0"]
#   security_group_id = aws_security_group.tpkube_secgroup.id
# }

# resource "aws_security_group_rule" "https" {
#   type              = "ingress"
#   from_port        = 443
#   to_port          = 443
#   protocol         = "tcp"
#   cidr_blocks      = ["0.0.0.0/0"]
#   ipv6_cidr_blocks = ["::/0"]
#   security_group_id = aws_security_group.tpkube_secgroup.id
# }

resource "aws_security_group_rule" "guacamole" {
  type              = "ingress"
  from_port        = 8080
  to_port          = 8080
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_key_pair" "tpkube_key" {
  key_name   = "guacamole_key"
  public_key = "${file("guacamole_key.pub")}"
}


variable "vm_number" {
  type = number
  default = 1
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
      # vars={
      #   cloudus_user_passwd = var.cloudus_user_passwd
      #   ec2_user_passwd = var.ec2_user_passwd
      # }
}

resource "aws_instance" "tpkube-instance" {
  count   = var.vm_number

  # ami           = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  # ami             = "ami-0620e345b7096a4ea"   # ROckyLinux8
  # ami             = "ami-004b161a1cceb1ceb"   # Rocky-8-ec2-8.6-20220515.0.x86_64-d6577ceb-8ea8-4e0e-84c6-f098fc302e82    
      # https://aws.amazon.com/marketplace/pp/prodview-2otariyxb3mqu
      # I did a subscription on AWS to this free ROckyLinux in market place (with centrale account)
  ami             = "ami-0728c171aa8e41159"   # Amazon Linux 2 with .NET 6, PowerShell, Mono, and MATE Desktop Environment
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.tpkube_secgroup.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 20 # in GB
  }

}

output "tpkube-instance-ip" {
  value = aws_instance.tpkube-instance[*].public_ip
}

