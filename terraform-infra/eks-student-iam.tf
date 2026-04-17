locals {
  eks_student_iam_enabled = var.eks_cluster_count > 0
}

resource "aws_iam_user" "eks_student" {
  count = local.eks_student_iam_enabled ? var.vm_number : 0

  name          = format("eks-vm%02d", count.index)
  force_destroy = true

  tags = {
    provisioned_by = "tf-code"
  }
}

resource "aws_iam_access_key" "eks_student" {
  count = local.eks_student_iam_enabled ? var.vm_number : 0

  user = aws_iam_user.eks_student[count.index].name
}

resource "aws_iam_user_policy" "eks_student_describe_cluster" {
  count = local.eks_student_iam_enabled ? var.vm_number : 0

  name = format("eks-student-describe-cluster-vm%02d", count.index)
  user = aws_iam_user.eks_student[count.index].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDescribeTrainingClusters"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = [
          for cluster in aws_eks_cluster.training : cluster.arn
        ]
      }
    ]
  })
}

output "eks_iam_students" {
  sensitive = true
  value = local.eks_student_iam_enabled ? {
    for i in range(var.vm_number) :
    format("vm%02d", i) => {
      iam_user_name     = aws_iam_user.eks_student[i].name
      iam_user_arn      = aws_iam_user.eks_student[i].arn
      access_key_id     = aws_iam_access_key.eks_student[i].id
      secret_access_key = aws_iam_access_key.eks_student[i].secret
      region            = data.aws_region.current.name
    }
  } : {}
}
