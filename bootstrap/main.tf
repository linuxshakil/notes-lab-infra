############################################################
# BOOTSTRAP  (run ONCE, by a human, with your MFA-protected login, see 00-RUNBOOK.md)
#
# Creates the things Terraform itself needs before anything
# else can be automated:
#   1. S3 bucket for remote state (native S3 locking, no DynamoDB)
#   2. GitHub OIDC provider  -> no AWS access keys in GitHub, ever
#   3. Two CI roles for THIS repo:
#        - plan  role : read-only, usable from pull requests
#        - apply role : admin, usable ONLY from the protected
#                       GitHub Environment "production-infra"
#   4. CloudTrail (audit log) and a monthly Budget alarm
############################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
      Layer     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

############################################################
# 1. Terraform state bucket
############################################################

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

data "aws_iam_policy_document" "tf_state_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.tf_state_tls_only.json
}

############################################################
# 2. GitHub OIDC provider
#    (AWS validates GitHub's certificate chain itself these days;
#     the thumbprint below is only kept because older provider
#     versions still expect a value.)
############################################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

############################################################
# 3a. PLAN role  (pull requests)  — read only
############################################################

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.infra_repo}:pull_request",
        "repo:${var.github_org}/${var.infra_repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "tf_plan" {
  name                 = "${var.name}-gha-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tf_state.arn]
  }
}

resource "aws_iam_role_policy" "tf_plan_state" {
  name   = "read-terraform-state"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.plan_state_read.json
}

############################################################
# 3b. APPLY role — can only be assumed by jobs that run in the
#     GitHub Environment "production-infra" (which you protect
#     with "Required reviewers"). A PR from a fork or a random
#     branch cannot get this role.
############################################################

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.infra_repo}:environment:production-infra"]
    }
  }
}

resource "aws_iam_role" "tf_apply" {
  name                 = "${var.name}-gha-terraform-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# Trade-off, stated honestly: Terraform creates VPC, EKS, IAM, RDS, KMS...
# so scoping this down perfectly is a project of its own. The protection
# here is WHO can assume it (one repo + one approved environment), not
# what it can do. Tighten later (permission boundary / SCP).
resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

############################################################
# 4a. CloudTrail  (the first copy of management events is free)
############################################################

resource "aws_s3_bucket" "trail" {
  bucket = "${var.name}-${local.account_id}-cloudtrail"
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expire-after-180-days"
    status = "Enabled"
    filter {}
    expiration {
      days = 180
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.trail.arn,
      "${aws_s3_bucket.trail.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.trail]
}

############################################################
# 4b. Budget alarm — EKS + NAT + RDS keep billing while idle
############################################################

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}

############################################################
# 5. HUMAN ACCESS  (no Okta / no Identity Center needed)
#
#   You  --password+MFA-->  IAM user "lab-operator" (zero permissions)
#        --assume + MFA code-->  role  <name>-admin     (daily admin work, 4h)
#                           or   role  <name>-readonly  (looking around)
#
# Why this is safe: a stolen password alone is useless, because the
# roles refuse anyone who did not type a fresh MFA code. There are no
# long-lived access keys anywhere.
############################################################

data "aws_iam_user" "operator" {
  user_name = var.operator_user_name
}

data "aws_iam_policy_document" "human_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_user.operator.arn]
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "admin" {
  name                 = "${var.name}-admin"
  assume_role_policy   = data.aws_iam_policy_document.human_trust.json
  max_session_duration = 14400 # 4 hours
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "readonly" {
  name                 = "${var.name}-readonly"
  assume_role_policy   = data.aws_iam_policy_document.human_trust.json
  max_session_duration = 14400
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# The ONLY permissions the IAM user itself has.
data "aws_iam_policy_document" "operator" {
  statement {
    sid     = "AssumeHumanRoles"
    actions = ["sts:AssumeRole"]
    resources = [
      aws_iam_role.admin.arn,
      aws_iam_role.readonly.arn,
    ]
  }

  # needed by `aws login` (short-lived CLI credentials, no access keys)
  statement {
    sid       = "AwsLoginForCli"
    actions   = ["signin:AuthorizeOAuth2Access", "signin:CreateOAuth2Token"]
    resources = ["*"]
  }

  # let the user manage ONLY their own password and MFA device
  statement {
    sid = "ManageOwnPasswordAndMfa"
    actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:DeactivateMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:user/$${aws:username}",
      "arn:aws:iam::${local.account_id}:mfa/$${aws:username}",
    ]
  }

  statement {
    sid       = "ListVirtualMfaDevices"
    actions   = ["iam:ListVirtualMFADevices"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "operator" {
  name   = "${var.name}-operator-assume-roles"
  policy = data.aws_iam_policy_document.operator.json
}

resource "aws_iam_user_policy_attachment" "operator" {
  user       = var.operator_user_name
  policy_arn = aws_iam_policy.operator.arn
}

############################################################
# 6. ACCOUNT HARDENING (guard-rails that apply to the whole account)
############################################################

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# No bucket in this account can ever be made public by mistake
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Every new EBS volume (node disks etc.) is encrypted by default
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# Every new EC2 instance must use IMDSv2 (blocks a classic credential-theft attack)
resource "aws_ec2_instance_metadata_defaults" "this" {
  http_tokens = "required"
}

# Free: warns you if any resource is shared outside this account
resource "aws_accessanalyzer_analyzer" "this" {
  analyzer_name = "${var.name}-analyzer"
  type          = "ACCOUNT"
}

resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}
