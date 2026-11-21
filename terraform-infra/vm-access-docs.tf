

data "aws_ami_ids" "access_docs_current" {
  count  = var.ami_source == "packer" && var.AccessDocs_vm_enabled ? 1 : 0
  owners = ["self"]

  filter {
    name   = "name"
    values = ["tpcs-access-docs-current"]
  }
  filter {
    name   = "tag:Repository"
    values = ["tpcs-workstations"]
  }
  filter {
    name   = "tag:TPCSImageProfile"
    values = ["access-docs"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  standard_access_docs_ami     = "ami-01d21b7be69801c2f"
  access_docs_current_ami_ids  = try(data.aws_ami_ids.access_docs_current[0].ids, [])
  access_docs_custom_ami_found = length(local.access_docs_current_ami_ids) == 1
  access_docs_ami              = var.ami_source == "packer" && local.access_docs_custom_ami_found ? local.access_docs_current_ami_ids[0] : local.standard_access_docs_ami
}

check "access_docs_current_ami" {
  assert {
    condition     = var.ami_source != "packer" || !var.AccessDocs_vm_enabled || local.access_docs_custom_ami_found
    error_message = "No unique current access/docs Packer AMI was found; access/docs will use the standard Ubuntu image."
  }
}

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
        users_list   = ["access"]
        key_pub      = file("key.pub")
      }
    )
  }
}

resource "aws_instance" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0

  ami                    = local.access_docs_ami
  instance_type          = var.access_docs_flavor
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
    ignore_changes = [user_data, ami]
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
            "eks:ListNodegroups", "eks:DescribeNodegroup",
            "autoscaling:DescribeAutoScalingGroups", "cloudwatch:GetMetricStatistics",
            "eks:DescribeCluster", "eks:ListClusters", "eks:AccessKubernetesApi", "eks:UpdateClusterConfig", "eks:DescribeUpdate",
            "eks:CreateAccessEntry", "eks:AssociateAccessPolicy", "eks:DescribeAccessEntry", "eks:ListAccessEntries", "eks:ListAssociatedAccessPolicies",
            "ec2:DescribeVpcs",
            "ec2:DescribeSubnets",
            "ec2:DescribeRouteTables",
            "ec2:DescribeNetworkAcls",
            "ec2:DescribeNatGateways",
            "ec2:DescribeInternetGateways",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeAddresses",
            "ec2:DescribeVolumes", "ec2:DescribeSnapshots", "ec2:DescribeNetworkInterfaces",
            "cloudwatch:GetMetricData",
            "elasticloadbalancing:DescribeLoadBalancers",
            "elasticloadbalancing:DescribeTags",
            "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth"],
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

resource "aws_iam_role_policy_attachment" "access_eks_cluster_policy" {
  count      = var.AccessDocs_vm_enabled ? 1 : 0
  role       = aws_iam_role.access[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
