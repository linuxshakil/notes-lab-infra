locals {
  app_subject = var.app_repo_subject != "" ? var.app_repo_subject : "${var.github_org}/${var.app_repo}"
}

############################################################
# GitHub Actions role for the APP repo: may ONLY push images to
# this one ECR repository, and only from the main branch.
# It has no access to EKS, RDS, S3 or anything else.
############################################################

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "app_ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.app_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "app_ci" {
  name               = "${var.name}-gha-app-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.app_ci_trust.json
}

data "aws_iam_policy_document" "app_ci" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "app_ci" {
  name   = "ecr-push"
  role   = aws_iam_role.app_ci.id
  policy = data.aws_iam_policy_document.app_ci.json
}
