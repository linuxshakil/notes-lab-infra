# Humans use the roles created in bootstrap (<name>-admin / <name>-readonly,
# MFA required). We map those roles into Kubernetes with EKS access entries
# (the modern way; no aws-auth ConfigMap editing).
data "aws_iam_role" "human_admin" {
  name = "${var.name}-admin"
}

data "aws_iam_role" "human_readonly" {
  name = "${var.name}-readonly"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_public_access_cidrs

  # The identity that creates the cluster (the CI apply role) becomes
  # cluster-admin, so the addons layer can install Helm charts.
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    human_admin = {
      principal_arn = data.aws_iam_role.human_admin.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    human_readonly = {
      principal_arn = data.aws_iam_role.human_readonly.arn
      policy_associations = {
        view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 30

  cluster_addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
      # Enables Kubernetes NetworkPolicy enforcement in the VPC CNI
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }
}
