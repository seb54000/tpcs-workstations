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

resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all inbound/outbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

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

###
###  All here is needed only for DNS auto update (need hostedZone configurerd via another terraform script)
variable "vm_dns_record" {
  type = string
  default = "vm1.tpkube.multiseb.com"
}

data "aws_route53_zone" "tpkube" {
  name         = "tpkube.multiseb.com."
}

resource "aws_route53_record" "tpkube_vm" {
  zone_id = data.aws_route53_zone.tpkube.zone_id
  name    = var.vm_dns_record
  type    = "A"
  ttl     = "60"
  records = [aws_instance.tpkube-instance.public_ip]
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
                "Action": "ec2:DescribeTags",
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

### End of block for DNS AUTO update
#### 


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
  # ami           = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  ami             = "ami-0728c171aa8e41159"   # Amazon Linux 2 with .NET 6, PowerShell, Mono, and MATE Desktop Environment
  instance_type = "t2.medium"
  iam_instance_profile = "${aws_iam_instance_profile.tpkube_profile.name}"
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  key_name      = aws_key_pair.tpkube_key.key_name
  user_data     = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 20 # in GB
  }

  tags = {
    tpcentrale = "tpcentrale"
    AUTO_DNS_NAME = var.vm_dns_record
    AUTO_DNS_ZONE = data.aws_route53_zone.tpkube.zone_id
  }
}

output "tpkube-instance-ip" {
  value = aws_instance.tpkube-instance.public_ip
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

# Know my external/public IP from within the VM :
# MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4/)