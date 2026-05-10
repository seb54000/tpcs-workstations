locals {
  ecr_students_enabled = var.eks_cluster_count > 0
}

data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "student" {
  count = local.ecr_students_enabled ? var.vm_number : 0

  name                 = format("vm%02d", count.index)
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "tpmon_demoboard" {
  count = local.ecr_students_enabled ? 1 : 0

  name                 = "tpmon-demoboard"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_lifecycle_policy" "student" {
  count = local.ecr_students_enabled ? var.vm_number : 0

  repository = aws_ecr_repository.student[count.index].name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 50 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 50
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "tpmon_demoboard" {
  count = local.ecr_students_enabled ? 1 : 0

  repository = aws_ecr_repository.tpmon_demoboard[0].name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 50 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 50
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_iam_user" "ecr_student" {
  count = local.ecr_students_enabled ? var.vm_number : 0

  name          = format("ecr-vm%02d", count.index)
  force_destroy = true

  tags = {
    provisioned_by = "tf-code"
  }
}

resource "aws_iam_access_key" "ecr_student" {
  count = local.ecr_students_enabled ? var.vm_number : 0

  user = aws_iam_user.ecr_student[count.index].name
}

resource "aws_iam_user_policy" "ecr_student_repo" {
  count = local.ecr_students_enabled ? var.vm_number : 0

  name = format("ecr-student-policy-vm%02d", count.index)
  user = aws_iam_user.ecr_student[count.index].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "AllowPushPullOnOwnAndSharedRepositoriesInParis"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = [
          aws_ecr_repository.student[count.index].arn,
          aws_ecr_repository.tpmon_demoboard[0].arn
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "eu-west-3"
          }
        }
      }
    ]
  })
}

output "ecr_students" {
  sensitive = true
  value = local.ecr_students_enabled ? {
    for i in range(var.vm_number) :
    format("vm%02d", i) => {
      iam_user_name     = aws_iam_user.ecr_student[i].name
      access_key_id     = aws_iam_access_key.ecr_student[i].id
      secret_access_key = aws_iam_access_key.ecr_student[i].secret
      repository_name   = aws_ecr_repository.student[i].name
      repository_url    = aws_ecr_repository.student[i].repository_url
      registry_host     = format("%s.dkr.ecr.eu-west-3.amazonaws.com", data.aws_caller_identity.current.account_id)
      region            = "eu-west-3"
      docker_login_cmd  = format("aws ecr get-login-password --region eu-west-3 --profile ecr | docker login --username AWS --password-stdin %s.dkr.ecr.eu-west-3.amazonaws.com", data.aws_caller_identity.current.account_id)
      image_example     = format("%s.dkr.ecr.eu-west-3.amazonaws.com/%s:front-v1", data.aws_caller_identity.current.account_id, aws_ecr_repository.student[i].name)
    }
  } : {}
}

output "ecr_tpmon_demoboard" {
  value = local.ecr_students_enabled ? {
    repository_name = aws_ecr_repository.tpmon_demoboard[0].name
    repository_url  = aws_ecr_repository.tpmon_demoboard[0].repository_url
    registry_host   = format("%s.dkr.ecr.eu-west-3.amazonaws.com", data.aws_caller_identity.current.account_id)
    region          = "eu-west-3"
    image_api_v1    = format("%s:api-v1", aws_ecr_repository.tpmon_demoboard[0].repository_url)
    image_worker_v1 = format("%s:worker-v1", aws_ecr_repository.tpmon_demoboard[0].repository_url)
    image_front_v2  = format("%s:front-v2", aws_ecr_repository.tpmon_demoboard[0].repository_url)
  } : {}
}
