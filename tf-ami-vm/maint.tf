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

resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port        = 80
  to_port          = 80
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port        = 443
  to_port          = 443
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

# resource "aws_security_group_rule" "vikunja_front_port" {
#   type              = "ingress"
#   from_port        = 8080
#   to_port          = 8080
#   protocol         = "tcp"
#   cidr_blocks      = ["0.0.0.0/0"]
#   ipv6_cidr_blocks = ["::/0"]
#   security_group_id = aws_security_group.tpkube_secgroup.id
# }

# resource "aws_security_group_rule" "vikunja_api_port" {
#   type              = "ingress"
#   from_port        = 3456
#   to_port          = 3456
#   protocol         = "tcp"
#   cidr_blocks      = ["0.0.0.0/0"]
#   ipv6_cidr_blocks = ["::/0"]
#   security_group_id = aws_security_group.tpkube_secgroup.id
# }

resource "aws_security_group_rule" "node_port_kube_test" {
  type              = "ingress"
  from_port        = 8888
  to_port          = 8888
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_security_group_rule" "node_port_kube_test_2" {
  type              = "ingress"
  from_port        = 8889
  to_port          = 8889
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_security_group_rule" "node_port_kube3_test" {
  type              = "ingress"
  from_port        = 30888
  to_port          = 30888
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_security_group_rule" "xrdp_port" {
  type              = "ingress"
  from_port        = 3389
  to_port          = 3389
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_security_group_rule" "micro_k8s_api" {
  type              = "ingress"
  from_port        = 16443
  to_port          = 16443
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.tpkube_secgroup.id
}

resource "aws_key_pair" "tpkube_key" {
  key_name   = "tpkube_key"
  public_key = "${file("key.pub")}"
}

variable "cloudus_user_passwd" {
  type = string
}
variable "ec2_user_passwd" {
  type = string
}
variable "iac_user_passwd" {
  type = string
}

variable "kube_vm_number" {
  type = number
  default = 1
}
variable "iac_vm_number" {
  type = number
  default = 0
}

variable "vm_dns_record_suffix" {
  type = string
  default = "tpkube.multiseb.com"
}

# data "aws_route53_zone" "tpkube" {
#   name         = "${var.vm_dns_record_suffix}."
# }

resource "ovh_domain_zone_record" "tpkube_vm" {
  count   = var.kube_vm_number
  # zone      = "${var.vm_dns_record_suffix}"
  zone      = "multiseb.com"
  # subdomain = "vm${count.index}.${var.vm_dns_record_suffix}"
  subdomain = "vm${count.index}.tpkube"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.tpkube-instance[count.index].public_ip
}

# resource "ovh_domain_zone_record" "tpkube_zone" {
#   count   = var.kube_vm_number
#   # zone      = "${var.vm_dns_record_suffix}"
#   zone      = "multiseb.com"
#   subdomain = "tpiac"
#   fieldtype = "NS"
#   ttl       = 60
#   target    = "ns.ovh.net." // will be route53 dynamic assigned adress later
# }

# resource "aws_route53_record" "tpkube_vm" {
#   count   = var.kube_vm_number
#   zone_id = data.aws_route53_zone.tpkube.zone_id
#   name    = "vm${count.index}.${var.vm_dns_record_suffix}"
#   type    = "A"
#   ttl     = "60"
#   records = [aws_instance.tpkube-instance[count.index].public_ip]
# }

# resource "aws_iam_role" "tpkube_role" {
#   name = "tpkube_role"

#   assume_role_policy = jsonencode(
#     {
#       "Version": "2012-10-17",
#       "Statement": [
#         {
#           "Action": "sts:AssumeRole",
#           "Principal": {
#             "Service": "ec2.amazonaws.com"
#           },
#           "Effect": "Allow",
#           "Sid": ""
#         }
#       ]
#     }
#   )

#   tags = {
#       tpcentrale = "tpcentrale"
#   }
# }

# resource "aws_iam_instance_profile" "tpkube_profile" {
#   name = "tpkube_profile"
#   role = "${aws_iam_role.tpkube_role.name}"
# }

# resource "aws_iam_policy" "tpkube_policy" {
#   name = "tpkube_policy"

#   policy = jsonencode(
#     {
#         "Version": "2012-10-17",
#         "Statement": [
#             {
#                 "Effect": "Allow",
#                 "Action": ["ec2:DescribeTags", "ec2:DescribeInstances"],
#                 "Resource": "*"
#             },
#             {
#                 "Effect": "Allow",
#                 "Action": "route53:ChangeResourceRecordSets",
#                 "Resource": "arn:aws:route53:::hostedzone/${data.aws_route53_zone.tpkube.zone_id}"
#             }
#         ]
#     }
#   )
# }

# resource "aws_iam_policy_attachment" "tpkube_attach" {
#   name       = "tpkube_attach"
#   roles      = ["${aws_iam_role.tpkube_role.name}"]
#   policy_arn = "${aws_iam_policy.tpkube_policy.arn}"
# }


# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are not TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "user_data" {
      template = file("user_data.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        ec2_user_passwd = var.ec2_user_passwd
      }
}

resource "aws_instance" "tpkube-instance" {
  count   = var.kube_vm_number

  # ami           = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  # ami             = "ami-0728c171aa8e41159"   # Amazon Linux 2 with .NET 6, PowerShell, Mono, and MATE Desktop Environment
  ami             = "ami-004dac467bb041dc7"   # us-east-1 : Ubuntu 22.04 LTS Jammy jellifish
  instance_type = "t2.medium"
  # iam_instance_profile = "${aws_iam_instance_profile.tpkube_profile.name}"
  vpc_security_group_ids = [aws_security_group.tpkube_secgroup.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 20 # in GB
  }

  tags = {
    tpcentrale = "tpcentrale"
    AUTO_DNS_NAME = "vm${count.index}.${var.vm_dns_record_suffix}"
    # AUTO_DNS_ZONE = data.aws_route53_zone.tpkube.zone_id
    Name = "tpkube-vm${count.index}"
  }

  lifecycle {
    ignore_changes = [ user_data, instance_type ]
  }
}

resource "aws_ec2_instance_state" "tpkube-instance" {
  count   = var.kube_vm_number
  instance_id = aws_instance.tpkube-instance[count.index].id
  state       = "running"
}

output "tpkube-instance-ip" {
  value = [
    {
    "public_ip" = aws_instance.tpkube-instance[*].public_ip
    # "name" = aws_instance.tpkube-instance[*].tags["Name"]
    "dns" = ovh_domain_zone_record.tpkube_vm[*].subdomain
    }
  ]
}



# Simple Webserver VM to display info table

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "user_data_serverinfo" {
      template = file("user_data_serverinfo.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        ec2_user_passwd = var.ec2_user_passwd
      }
}

variable "serverinfo_enabled" {
  type = bool
  default = true
}

resource "aws_instance" "tpkube-serverinfo" {
  count = "${var.serverinfo_enabled ? 1 : 0}"

  ami             = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  instance_type = "t2.micro"
  # iam_instance_profile = "${aws_iam_instance_profile.tpkube_profile.name}"
  vpc_security_group_ids = [aws_security_group.tpkube_secgroup.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data_serverinfo.rendered

  tags = {
    tpcentrale = "tpcentrale"
    AUTO_DNS_NAME = "serverinfo.${var.vm_dns_record_suffix}"
    # AUTO_DNS_ZONE = data.aws_route53_zone.tpkube.zone_id
    Name = "tpkube-serverinfo"
  }
}

# resource "aws_route53_record" "tpkube_vm_serverinfo" {
#   count = "${var.serverinfo_enabled ? 1 : 0}"
#   zone_id = data.aws_route53_zone.tpkube.zone_id
#   name    = "serverinfo.${var.vm_dns_record_suffix}"
#   type    = "A"
#   ttl     = "60"
#   records = [aws_instance.tpkube-serverinfo[*].public_ip]
# }

output "tpkube-serverinfo" {
  value = aws_instance.tpkube-serverinfo[*].public_ip
}

resource "aws_ec2_instance_state" "tpkube-serverinfo" {
  count = "${var.serverinfo_enabled ? 1 : 0}"
  instance_id = aws_instance.tpkube-serverinfo[count.index].id
  state       = "running"
}

# VM for IaC (Ansible, terraform)

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "user_data_tpiac" {
      template = file("user_data_tpiac.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        iac_user_passwd = var.iac_user_passwd
        ec2_user_passwd = var.ec2_user_passwd
      }
}


resource "aws_instance" "tpiac-vm" {
  count   = var.iac_vm_number
  # ami     = "ami-0728c171aa8e41159"   # Amazon Linux 2 with .NET 6, PowerShell, Mono, and MATE Desktop Environment
  ami             = "ami-004dac467bb041dc7"   # us-east-1 : Ubuntu 22.04 LTS Jammy jellifish
  instance_type = "t2.medium"
  # iam_instance_profile = "${aws_iam_instance_profile.tpkube_profile.name}"
  vpc_security_group_ids = [aws_security_group.tpkube_secgroup.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data_tpiac.rendered

  tags = {
    tpcentrale = "tpcentrale"
    AUTO_DNS_NAME = "vmiac.${var.vm_dns_record_suffix}"
    # AUTO_DNS_ZONE = data.aws_route53_zone.tpkube.zone_id
    Name = "tpiac-vm${count.index}"
  }
}

resource "ovh_domain_zone_record" "tpiac_vm" {
  count   = var.iac_vm_number
  # zone      = "${var.vm_dns_record_suffix}"
  zone      = "multiseb.com"
  # subdomain = "vm${count.index}.${var.vm_dns_record_suffix}"
  subdomain = "vm${count.index}.tpiac"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.tpiac-vm[count.index].public_ip
}

# resource "aws_route53_record" "tpkube_vm_iac" {
#   count   = var.iac_vm_number
#   zone_id = data.aws_route53_zone.tpkube.zone_id
#   name    = "vmiac${count.index}.${var.vm_dns_record_suffix}"
#   type    = "A"
#   ttl     = "60"
#   records = [aws_instance.tpiac-vm[count.index].public_ip]
# }

output "tpiac-vm" {
    value = [
    {
    "public_ip" = aws_instance.tpiac-vm[*].public_ip
    # "name" = aws_instance.tpic-vm[*].tags["Name"]
    "dns" = ovh_domain_zone_record.tpiac_vm[*].subdomain
    }
  ]
}

resource "aws_ec2_instance_state" "tpiac-vm" {
  count   = var.iac_vm_number
  instance_id = aws_instance.tpiac-vm[count.index].id
  state       = "running"
}