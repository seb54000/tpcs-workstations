variable "eks_cluster_count" {
  type        = number
  description = "Number of EKS clusters to provision (independent from students count)."
  default     = 0
}

variable "eks_cluster_prefix" {
  type        = string
  description = "Name prefix for EKS clusters."
  default     = "eks-training"
}

variable "eks_kubernetes_version" {
  type        = string
  description = "Kubernetes version for EKS. Empty string lets AWS select the latest default."
  default     = ""
}

variable "eks_node_instance_type" {
  type        = string
  description = "EC2 instance type for managed node groups."
  default     = "t3.medium"
}

variable "eks_node_count" {
  type        = number
  description = "Number of worker nodes per cluster (forced to 3 for one node per AZ)."
  default     = 3
}

locals {
  eks_subnet_ids = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id,
    aws_subnet.public_subnet_3.id
  ]
}

data "aws_region" "current" {}

resource "aws_iam_role" "eks_cluster" {
  name = "tpcs-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  lifecycle {
    precondition {
      condition     = var.eks_node_count == 3
      error_message = "eks_node_count must be 3 to force one worker node per AZ (3 AZ)."
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodegroup" {
  name = "tpcs-eks-nodegroup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_nodegroup_worker_policy" {
  role       = aws_iam_role.eks_nodegroup.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_nodegroup_cni_policy" {
  role       = aws_iam_role.eks_nodegroup.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_nodegroup_ecr_ro_policy" {
  role       = aws_iam_role.eks_nodegroup.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "training" {
  count = var.eks_cluster_count

  name     = format("%s-%02d", var.eks_cluster_prefix, count.index)
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_kubernetes_version != "" ? var.eks_kubernetes_version : null

  vpc_config {
    subnet_ids              = local.eks_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

resource "aws_eks_node_group" "training" {
  count = var.eks_cluster_count * var.eks_node_count

  cluster_name = aws_eks_cluster.training[floor(count.index / var.eks_node_count)].name
  node_group_name = format(
    "ng-%02d-az%d",
    floor(count.index / var.eks_node_count),
    (count.index % var.eks_node_count) + 1
  )
  node_role_arn  = aws_iam_role.eks_nodegroup.arn
  subnet_ids     = [local.eks_subnet_ids[count.index % var.eks_node_count]]
  instance_types = [var.eks_node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodegroup_worker_policy,
    aws_iam_role_policy_attachment.eks_nodegroup_cni_policy,
    aws_iam_role_policy_attachment.eks_nodegroup_ecr_ro_policy
  ]
}

output "eks_clusters" {
  description = "EKS clusters metadata and kubeconfig generation command."
  value = {
    for idx, cluster in aws_eks_cluster.training :
    format("cluster%02d", idx) => {
      cluster_name               = cluster.name
      region                     = data.aws_region.current.name
      endpoint                   = cluster.endpoint
      certificate_authority_data = cluster.certificate_authority[0].data
      node_group_names = [
        format("ng-%02d-az1", idx),
        format("ng-%02d-az2", idx),
        format("ng-%02d-az3", idx)
      ]
      kubeconfig_command = format(
        "aws eks update-kubeconfig --region %s --name %s --alias %s",
        data.aws_region.current.name,
        cluster.name,
        format("cluster%02d", idx)
      )
    }
  }
}
