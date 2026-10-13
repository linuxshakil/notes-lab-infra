# One uploads bucket per environment (this is the "storage" half of the app).
# Versioning is ON from day one: it is the prerequisite for cross-region
# replication when you build DR.
resource "aws_s3_bucket" "uploads" {
  for_each = var.environments

  bucket        = "${var.name}-${data.aws_caller_identity.current.account_id}-${each.key}-uploads"
  force_destroy = each.key != "prod"
}

resource "aws_s3_bucket_versioning" "uploads" {
  for_each = var.environments

  bucket = aws_s3_bucket.uploads[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  for_each = var.environments

  bucket = aws_s3_bucket.uploads[each.key].id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.env[each.key].arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  for_each = var.environments

  bucket                  = aws_s3_bucket.uploads[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  for_each = var.environments

  bucket = aws_s3_bucket.uploads[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  for_each = var.environments

  bucket = aws_s3_bucket.uploads[each.key].id

  rule {
    id     = "housekeeping"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "uploads_tls" {
  for_each = var.environments

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.uploads[each.key].arn,
      "${aws_s3_bucket.uploads[each.key].arn}/*",
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

resource "aws_s3_bucket_policy" "uploads" {
  for_each = var.environments

  bucket = aws_s3_bucket.uploads[each.key].id
  policy = data.aws_iam_policy_document.uploads_tls[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.uploads]
}
