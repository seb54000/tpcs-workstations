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

variable "vm_number" {
  type = number
  default = 1
}

variable "vm_dns_record_suffix" {
  type = string
  default = "tpkube.multiseb.com"
}

data "aws_route53_zone" "tpkube" {
  name         = "${var.vm_dns_record_suffix}."
}

resource "aws_route53_record" "tpkube_vm" {
  count   = var.vm_number
  zone_id = data.aws_route53_zone.tpkube.zone_id
  name    = "vm${count.index}.${var.vm_dns_record_suffix}"
  type    = "A"
  ttl     = "60"
  records = [aws_instance.tpkube-instance[count.index].public_ip]
}

resource "aws_iam_role" "tpkube_role" {
  name = "tpkube_role"

  assume_role_policy = jsonencode(
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
  )

  tags = {
      tpcentrale = "tpcentrale"
  }
}

resource "aws_iam_instance_profile" "tpkube_profile" {
  name = "tpkube_profile"
  role = "${aws_iam_role.tpkube_role.name}"
}

resource "aws_iam_policy" "tpkube_policy" {
  name = "tpkube_policy"

  policy = jsonencode(
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["ec2:DescribeTags", "ec2:DescribeInstances"],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": "route53:ChangeResourceRecordSets",
                "Resource": "arn:aws:route53:::hostedzone/${data.aws_route53_zone.tpkube.zone_id}"
            }
        ]
    }
  )
}

resource "aws_iam_policy_attachment" "tpkube_attach" {
  name       = "tpkube_attach"
  roles      = ["${aws_iam_role.tpkube_role.name}"]
  policy_arn = "${aws_iam_policy.tpkube_policy.arn}"
}


# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "user_data" {
      template = file("user_data.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        ec2_user_passwd = var.ec2_user_passwd
      }
}

resource "aws_instance" "tpkube-instance" {
  count   = var.vm_number

  # ami           = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  ami             = "ami-0728c171aa8e41159"   # Amazon Linux 2 with .NET 6, PowerShell, Mono, and MATE Desktop Environment
  instance_type = "t2.medium"
  iam_instance_profile = "${aws_iam_instance_profile.tpkube_profile.name}"
  vpc_security_group_ids = [aws_security_group.tpkube_secgroup.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 20 # in GB
  }

  tags = {
    tpcentrale = "tpcentrale"
    AUTO_DNS_NAME = "vm${count.index}.${var.vm_dns_record_suffix}"
    AUTO_DNS_ZONE = data.aws_route53_zone.tpkube.zone_id
    Name = "tpkube-vm${count.index}"
  }
}

output "tpkube-instance-ip" {
  value = aws_instance.tpkube-instance[*].public_ip
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

resource "aws_instance" "tpkube-serverinfo" {

  ami             = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.tpkube_profile.name}"
  vpc_security_group_ids = [aws_security_group.tpkube_secgroup.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data_serverinfo.rendered

  tags = {
    tpcentrale = "tpcentrale"
    AUTO_DNS_NAME = "serverinfo.${var.vm_dns_record_suffix}"
    AUTO_DNS_ZONE = data.aws_route53_zone.tpkube.zone_id
    Name = "tpkube-serverinfo"
  }
}

resource "aws_route53_record" "tpkube_vm_serverinfo" {
  zone_id = data.aws_route53_zone.tpkube.zone_id
  name    = "serverinfo.${var.vm_dns_record_suffix}"
  type    = "A"
  ttl     = "60"
  records = [aws_instance.tpkube-serverinfo.public_ip]
}

output "tpkube-serverinfo" {
  value = aws_instance.tpkube-serverinfo.public_ip
}

# cd tp-centralesupelec/tf-ami-vm
# export AWS_ACCESS_KEY_ID=*************
# export AWS_SECRET_ACCESS_KEY=***************
# export AWS_DEFAULT_REGION=us-east-1

# export TF_VAR_ec2_user_passwd=$$$$$$$$$
# export TF_VAR_cloudus_user_passwd=$$$$$$$



# TPKUBE_IP=$(terraform output -raw tpkube-instance-ip)
# ssh -o StrictHostKeyChecking=no -i ~/.ssh/tpkube_key -L 33389:localhost:3389 ec2-user@${TPKUBE_IP}

# Depuis client XRDP, il faut se connecter à localhost:33389 on peut utiliser au choix le user cloudus ou ec2-user
# Debug cloud-init user_data commands : sudo less /var/log/cloud-init-output.log
#   et surtout : sudo less /var/log/user-data.log

# use carefully ::: terraform destroy -auto-approve && terraform apply -auto-approve && sleep 20 && TPKUBE_IP=$(terraform output -raw tpkube-instance-ip) && ssh -o StrictHostKeyChecking=no -i ~/.ssh/tpkube_key -L 33389:localhost:3389 ec2-user@${TPKUBE_IP}


# ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" -i ~/.ssh/tpkube_key -L 33389:localhost:3389 ec2-user@vm0.tpkube.multiseb.com
# ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" -i ~/.ssh/tpkube_key -L 33389:localhost:3389 ec2-user@vm1.tpkube.multiseb.com

# ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" -L 33389:localhost:3389 cloudus@vm1.tpkube.multiseb.com

# Know my external/public IP from within the VM :
# MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4/)