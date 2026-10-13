############################################################
# Pod -> AWS identity (IRSA): one role per environment.
# Trust is pinned to ServiceAccount <env>/notes-app, so a pod in
# namespace "dev" can NEVER assume the prod role.
############################################################

data "aws_iam_policy_document" "app_trust" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${each.key}:notes-app"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  for_each = var.environments

  name               = "${var.name}-${each.key}-app"
  assume_role_policy = data.aws_iam_policy_document.app_trust[each.key].json
}

data "aws_iam_policy_document" "app_access" {
  for_each = var.environments

  # S3: only this env's bucket
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.uploads[each.key].arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.uploads[each.key].arn}/*"]
  }

  # Secrets Manager: only this env's DB credentials
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.this[each.key].master_user_secret[0].secret_arn]
  }

  # KMS: only this env's key (S3 objects + the DB secret are encrypted with it)
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.env[each.key].arn]
  }
}

resource "aws_iam_role_policy" "app" {
  for_each = var.environments

  name   = "app-access"
  role   = aws_iam_role.app[each.key].id
  policy = data.aws_iam_policy_document.app_access[each.key].json
}

############################################################
# AWS Load Balancer Controller role (cluster-wide add-on)
############################################################

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name                              = "${var.name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
