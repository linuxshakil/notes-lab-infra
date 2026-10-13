output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_controller_role_arn" {
  value = module.alb_controller_irsa.iam_role_arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "app_ci_role_arn" {
  description = "Put in the app repo's GitHub VARIABLE AWS_ROLE_ARN"
  value       = aws_iam_role.app_ci.arn
}

# Everything the deployment repo needs, per environment.
# Consumed by notes-app-deploy/scripts/render-env-config.sh
output "environments" {
  value = {
    for env, _ in var.environments : env => {
      namespace      = env
      app_role_arn   = aws_iam_role.app[env].arn
      db_host        = aws_db_instance.this[env].address
      db_port        = aws_db_instance.this[env].port
      db_name        = aws_db_instance.this[env].db_name
      db_secret_arn  = aws_db_instance.this[env].master_user_secret[0].secret_arn
      uploads_bucket = aws_s3_bucket.uploads[env].bucket
      kms_key_arn    = aws_kms_key.env[env].arn
    }
  }
}
