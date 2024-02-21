# EKS CLUSTER ROLE
resource "aws_iam_role" "EKS_cluster_role" {
  name = "EKS_cluster_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

// This policy provides Kubernetes with the permissions it requires to manage resources on your behalf. Kubernetes requires Ec2:CreateTags permissions to place identifying information on EC2 resources including but not limited to Instances, Security Groups, and Elastic Network Interfaces
resource "aws_iam_role_policy_attachment" "EKS_cluster_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.EKS_cluster_role.name
}

//==============================================================================================
# NODE GROUP ROLE
resource "aws_iam_role" "node_group_role" {
  name = "node_group_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

//This policy allows Amazon EKS worker nodes to connect to Amazon EKS Clusters.
resource "aws_iam_role_policy_attachment" "EKS_worker_node_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

// This policy Provides read-only access to Amazon EC2 Container Registry repositories.
resource "aws_iam_role_policy_attachment" "EC2_container_registry_readOnly_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

// This policy provides the Amazon VPC CNI Plugin (amazon-vpc-cni-k8s) the permissions it requires to modify the IP address configuration on your EKS worker nodes. This permission set allows the CNI to list, describe, and modify Elastic Network Interfaces on your behalf
resource "aws_iam_role_policy_attachment" "EKS_cni_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

//==============================================================================================
# EBS CSI DRIVER ROLE
data "tls_certificate" "EKS_TLS_cert" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "EKS_openId_connect_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.EKS_TLS_cert.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "ebs_csi_driver_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.EKS_openId_connect_provider.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.EKS_openId_connect_provider.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver_role" {
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role_policy.json
  name               = "EKS_ebs_csi_driver_role"
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy_attachment" {
  role       = aws_iam_role.ebs_csi_driver_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

//==============================================================================================
// AUTO SCALING ROLE
resource "aws_iam_policy" "EKS_auto_scaling_policy" {
  name = "EKS_auto_scaling_policy"
  policy = jsonencode({
    Version: "2012-10-17",
    Statement: [
        {
            Effect: "Allow",
            Action: [
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeAutoScalingGroups",
                "ec2:DescribeLaunchTemplateVersions",
                "autoscaling:DescribeTags",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            Resource: "*"
        }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "EKS_auto_scaling_policy_attachment" {
  policy_arn = aws_iam_policy.EKS_auto_scaling_policy.arn
  role       = aws_iam_role.node_group_role.name
}

//==============================================================================================
# Optional: only if you use your own KMS key to encrypt EBS volumes
# TODO: replace arn:aws:kms:us-east-1:424432388155:key/7a8ea545-e379-4ac5-8903-3f5ae22ea847 with your KMS key id arn!
# resource "aws_iam_policy" "eks_ebs_csi_driver_kms" {
#   name = "KMS_Key_For_Encryption_On_EBS"

#   policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Action": [
#         "kms:CreateGrant",
#         "kms:ListGrants",
#         "kms:RevokeGrant"
#       ],
#       "Resource": ["arn:aws:kms:us-east-1:424432388155:key/7a8ea545-e379-4ac5-8903-3f5ae22ea847"],
#       "Condition": {
#         "Bool": {
#           "kms:GrantIsForAWSResource": "true"
#         }
#       }
#     },
#     {
#       "Effect": "Allow",
#       "Action": [
#         "kms:Encrypt",
#         "kms:Decrypt",
#         "kms:ReEncrypt*",
#         "kms:GenerateDataKey*",
#         "kms:DescribeKey"
#       ],
#       "Resource": ["arn:aws:kms:us-east-1:424432388155:key/7a8ea545-e379-4ac5-8903-3f5ae22ea847"]
#     }
#   ]
# }
# POLICY
# }

# resource "aws_iam_role_policy_attachment" "amazon_ebs_csi_driver_kms" {
#   role       = aws_iam_role.eks_ebs_csi_driver.name
#   policy_arn = aws_iam_policy.eks_ebs_csi_driver_kms.arn
# }
