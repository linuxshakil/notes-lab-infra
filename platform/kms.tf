# One customer-managed key per environment. It encrypts that env's RDS
# storage, its DB master secret and its S3 bucket. Per-env keys mean a
# dev role can never decrypt prod data even if S3/RDS permissions slip.
# (Also the building block for DR later: multi-Region keys.)
resource "aws_kms_key" "env" {
  for_each = var.environments

  description             = "${var.name}-${each.key} data key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "env" {
  for_each = var.environments

  name          = "alias/${var.name}-${each.key}"
  target_key_id = aws_kms_key.env[each.key].key_id
}
