
resource "aws_iam_user" "tpiac" {
  count = var.iac_vm_number

  name = format("iac%02s", count.index)
  force_destroy = true

  tags = {
    provisioned_by = "tf-code"
  }
}


resource "aws_iam_user_login_profile" "tpiac" {
  count = var.iac_vm_number

  user    = aws_iam_user.tpiac[count.index].name
}

resource "aws_iam_access_key" "tpiac" {
  count = var.iac_vm_number

  user    = aws_iam_user.tpiac[count.index].name
}

output "tpiac_users" {
  sensitive = true
  value = [
    for i in range(var.iac_vm_number) : {
      user_name = aws_iam_user.tpiac[i].name
      user_pwd  = aws_iam_user_login_profile.tpiac[i].password
      user_apikey = aws_iam_access_key.tpiac[i].id
      user_apikey_secret = aws_iam_access_key.tpiac[i].secret      
    }
  ]
}
# terraform output -json tpiac_users | jq .

resource "aws_iam_account_alias" "tpiac" {
  account_alias = "tpiac"
}
# https://tpiac.signin.aws.amazon.com/console/


resource "aws_iam_group" "tpiac" {
  name = "iac"
}

resource "aws_iam_user_group_membership" "tpiac" {
  count = var.iac_vm_number
  user = aws_iam_user.tpiac[count.index].name

  groups = [
    aws_iam_group.tpiac.name,
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/2.34.0/docs/guides/iam-policy-documents
resource "aws_iam_policy" "tpiac" {
  name        = "iac_policy"
  path        = "/"
  description = "Policy for TP IAC"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ec2:*",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "eu-west-3"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "vpc:*",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "eu-west-3"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "elasticloadbalancing:*",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "eu-west-3"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "compute-optimizer:*",
            "Resource": "*",
            # "Condition": {
            #     "StringEquals": {
            #         "aws:RequestedRegion": "eu-west-3"
            #     }
            # }
            # Needed to avoid error on AWS console (non blocking) about compute-optimizer even if you do not activate it....
        },
        {
            "Effect": "Allow",
            "Action": "cloudwatch:DescribeAlarms",
            "Resource": "*",
            # "Condition": {
            #     "StringEquals": {
            #         "aws:RequestedRegion": "eu-west-3"
            #     }
            # }
            # Needed to avoid error on AWS console (non blocking) about compute-optimizer even if you do not activate it....
        },
        {
            "Sid": "AllowManageOwnAccessKeys",
            "Effect": "Allow",
            "Action": [
                "iam:CreateAccessKey",
                "iam:DeleteAccessKey",
                "iam:ListAccessKeys",
                "iam:UpdateAccessKey",
                "iam:GetAccessKeyLastUsed"
            ],
            "Resource": "arn:aws:iam::*:user/$${aws:username}"
        }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "tpiac" {
  group      = aws_iam_group.tpiac.name
  policy_arn = aws_iam_policy.tpiac.arn
}