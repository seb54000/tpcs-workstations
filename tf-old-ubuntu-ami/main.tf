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


resource "aws_s3_bucket" "amis-vmdks-bucket-scl" {
  bucket = "amis-vmdks-bucket-scl"
  force_destroy = true

  tags = {
    tpcentrale = "tpcentrale"
  }    
}

resource "aws_s3_bucket_acl" "amis-vmdks-bucket-scl-acl" {
  bucket = aws_s3_bucket.amis-vmdks-bucket-scl.id
  acl    = "public-read"
}

resource "aws_s3_object" "k8sgui-file-in-bucket" {
  bucket = aws_s3_bucket.amis-vmdks-bucket-scl.id
  key    = "k8sgui-disk001.vmdk"
  source = "k8sgui-disk001.vmdk"
  acl    = "public-read"
}

resource "aws_s3_object" "k8s-file-in-bucket" {
  bucket = aws_s3_bucket.amis-vmdks-bucket-scl.id
  key    = "k8s-disk001.vmdk"
  source = "k8s-disk001.vmdk"
  acl    = "public-read"
}


resource "aws_iam_role" "vmimport" {
  name = "vmimport"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "Service": "vmie.amazonaws.com" },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals":{
                "sts:Externalid": "vmimport"
                }
            }
        }
    ]
  })

  tags = {
    tpcentrale = "tpcentrale"
  }
}


resource "aws_iam_role_policy" "role-policy" {
  name = "role-policy"
  role = aws_iam_role.vmimport.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket" 
            ],
            "Resource": [
                "arn:aws:s3:::amis-vmdks-bucket-scl",
                "arn:aws:s3:::amis-vmdks-bucket-scl/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject",
                "s3:GetBucketAcl"
            ],
            "Resource": [
                "arn:aws:s3:::amis-vmdks-bucket-scl",
                "arn:aws:s3:::amis-vmdks-bucket-scl/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:ModifySnapshotAttribute",
                "ec2:CopySnapshot",
                "ec2:RegisterImage",
                "ec2:Describe*"
            ],
            "Resource": "*"
        }
    ]
  })
}


resource "aws_ebs_snapshot_import" "ami-k8sgui-snap" {
  disk_container {
    format = "VMDK"
    user_bucket {
      s3_bucket = "amis-vmdks-bucket-scl"
      s3_key    = "k8sgui-disk001.vmdk"
    }
  }

  role_name = aws_iam_role.vmimport.name

  tags = {
    tpcentrale = "tpcentrale"
  }
}

resource "aws_ebs_snapshot_import" "ami-k8s-snap" {
  disk_container {
    format = "VMDK"
    user_bucket {
      s3_bucket = "amis-vmdks-bucket-scl"
      s3_key    = "k8s-disk001.vmdk"
    }
  }

  role_name = aws_iam_role.vmimport.name

  tags = {
    tpcentrale = "tpcentrale"
  }
}


resource "aws_ami" "ami-k8sgui" {
  name                = "ami-k8sgui"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  deprecation_time    = "2024-01-01T00:00:00Z"

  ebs_block_device {
    device_name = "/dev/xvda"
    snapshot_id = aws_ebs_snapshot_import.ami-k8sgui-snap.id
  }
  tags = {
    tpcentrale = "tpcentrale"
  }  
  # https://stackoverflow.com/questions/50937756/terraform-set-ami-permissions-to-public
  provisioner "local-exec" {
    command = "aws ec2 modify-image-attribute --image-id '${aws_ami.ami-k8sgui.id}' --launch-permission '{\"Add\":[{\"Group\":\"all\"}]}'"
  }
}

resource "aws_ami" "ami-k8s" {
  name                = "ami-k8s"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  deprecation_time    = "2024-01-01T00:00:00Z"

  ebs_block_device {
    device_name = "/dev/xvda"
    snapshot_id = aws_ebs_snapshot_import.ami-k8s-snap.id
  }
  tags = {
    tpcentrale = "tpcentrale"
  }

  # https://stackoverflow.com/questions/50937756/terraform-set-ami-permissions-to-public
  provisioner "local-exec" {
    command = "aws ec2 modify-image-attribute --image-id '${aws_ami.ami-k8s.id}' --launch-permission '{\"Add\":[{\"Group\":\"all\"}]}'"
  }
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

resource "aws_instance" "k8sgui-instance" {
  ami           = aws_ami.ami-k8sgui.id
  # instance_type = "t2.medium"
  instance_type = "t2.xlarge"
  vpc_security_group_ids = [aws_security_group.allow_all.id]

  tags = {
    tpcentrale = "tpcentrale"
  }
}

output "k8sgui-instance-ip" {
  value = aws_instance.k8sgui-instance.public_ip
}

resource "aws_instance" "k8s-instance" {
  ami           = aws_ami.ami-k8s.id
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.allow_all.id]

  tags = {
    tpcentrale = "tpcentrale"
  }
}

output "k8s-instance-ip" {
  value = aws_instance.k8s-instance.public_ip
}





# terraform output aws_instance.k8s-instance.private_ip


# K8SGUI_IP=$(terraform output -raw k8sgui-instance-ip)
# ssh -L 33389:localhost:3389 cloudus@${K8SGUI_IP}
# K8S_IP=$(terraform output aws_instance.k8s-instance.private_ip)
# ssh -L 33389:localhost:3389 cloudus@${K8S_IP}