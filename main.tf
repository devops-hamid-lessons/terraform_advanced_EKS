module "aws_vpc" {
  source          = "./aws-vpc-module"
  env_prefix      = var.env_prefix
  networking      = var.networking
  security_groups = var.security_groups
}

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_config.name
  role_arn = aws_iam_role.EKS_cluster_role.arn
  version  = var.cluster_config.version

  vpc_config {
    subnet_ids         = flatten([module.aws_vpc.public_subnets_id, module.aws_vpc.private_subnets_id])
    security_group_ids = flatten(module.aws_vpc.security_groups_id)
  }

  depends_on = [
    aws_iam_role_policy_attachment.EKS_cluster_policy_attachment
  ]

}

# NODE GROUP
resource "aws_eks_node_group" "cluster_node_groups" {
  for_each        = { for node_group in var.node_groups : node_group.name => node_group }
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = each.value.name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = flatten(module.aws_vpc.private_subnets_id)

  scaling_config {
    desired_size = try(each.value.scaling_config.desired_size, 2)
    max_size     = try(each.value.scaling_config.max_size, 3)
    min_size     = try(each.value.scaling_config.min_size, 1)
  }

  update_config {
    max_unavailable = try(each.value.update_config.max_unavailable, 1)
  }

  ami_type       = each.value.ami_type
  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  depends_on = [
    aws_iam_role_policy_attachment.EKS_worker_node_policy_attachment,
    aws_iam_role_policy_attachment.EC2_container_registry_readOnly_policy_attachment,
    aws_iam_role_policy_attachment.ebs_csi_driver_policy_attachment
  ]
}

resource "aws_eks_addon" "ebs_csi_driver_addon" {
  cluster_name      = aws_eks_cluster.eks_cluster.id
  addon_name        = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn
  resolve_conflicts = "OVERWRITE"
  //  addon_version     = each.value.version
}

resource "aws_eks_addon" "cluster_addons" {
  for_each          = { for addon in var.addons : addon.name => addon }
  cluster_name      = aws_eks_cluster.eks_cluster.id
  addon_name        = each.value.name
  resolve_conflicts = "OVERWRITE"
//  addon_version     = each.value.version
}

//resource "aws_iam_openid_connect_provider" "default" {
//  url             = "https://${local.oidc}"
//  client_id_list  = ["sts.amazonaws.com"]
//  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
//}