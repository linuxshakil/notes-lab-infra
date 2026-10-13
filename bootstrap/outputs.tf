output "state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "tf_plan_role_arn" {
  description = "Put in the GitHub repo VARIABLE TF_PLAN_ROLE_ARN"
  value       = aws_iam_role.tf_plan.arn
}

output "tf_apply_role_arn" {
  description = "Put in the GitHub repo VARIABLE TF_APPLY_ROLE_ARN"
  value       = aws_iam_role.tf_apply.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "admin_role_arn" {
  description = "Daily admin role for the human (needs MFA)"
  value       = aws_iam_role.admin.arn
}

output "readonly_role_arn" {
  value = aws_iam_role.readonly.arn
}
