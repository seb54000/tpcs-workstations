

data "cloudinit_config" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0

  gzip          = true
  base64_encode = true

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        hostname_new = "access"
        users_list = ["access"]
        key_pub = file("key.pub")
     }
    )
  }
}

resource "aws_instance" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0

  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = var.access_docs_flavor
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name               = aws_key_pair.tpcs_key.key_name
  user_data              = data.cloudinit_config.access[0].rendered
  iam_instance_profile   = aws_iam_instance_profile.access[0].name

  root_block_device {
    volume_size = 50
  }

  tags = {
    Name       = "access" # Used by ansible to log in
    Roles      = "access;docs;monitoring"
    dns_record = "access.${var.dns_subdomain}"
    other_name = "guacamole"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_ec2_instance_state" "access" {
  count       = var.AccessDocs_vm_enabled ? 1 : 0
  instance_id = aws_instance.access[0].id
  state       = "running"
}

output "access" {
  value = [
    {
      "public_ip" = join("", aws_instance.access.*.public_ip)
      # "name" = aws_instance.access[*].tags["Name"]
      "dns" = join("", cloudflare_dns_record.access.*.name)
    }
  ]
}


####################
## IAM role management to allow this instance to call EC2 API (to list VMs and other php scripts)
# https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html
resource "aws_iam_role" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0
  name  = "access"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Effect" : "Allow",
          "Sid" : ""
        }
      ]
    }
  )

  tags = {
    name = "access-tpcs"
  }
}

resource "aws_iam_instance_profile" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0
  name  = "access"
  role  = aws_iam_role.access[0].name
}

resource "aws_iam_policy" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0
  name  = "access"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : ["ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions", "ec2:DescribeAccountAttributes", "servicequotas:*", "iam:ListGroupsForUser",
          "ec2:DescribeVpcs",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeAddresses"],
          "Resource" : "*"
        }
        # TOOO add authorization to request IAM informations including AK/SK ?
        #,
        # {
        #     "Effect": "Allow",
        #     "Action": "route53:ChangeResourceRecordSets",
        #     "Resource": "arn:aws:route53:::hostedzone/${data.aws_route53_zone.tpkube.zone_id}"
        # }
      ]
    }
  )
}

resource "aws_iam_policy_attachment" "access" {
  count      = var.AccessDocs_vm_enabled ? 1 : 0
  name       = "access"
  roles      = ["${aws_iam_role.access[0].name}"]
  policy_arn = aws_iam_policy.access[0].arn
}
