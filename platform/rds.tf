resource "aws_security_group" "rds" {
  for_each = var.environments

  name        = "${var.name}-${each.key}-rds"
  description = "MySQL from EKS nodes only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "MySQL from EKS worker nodes (pods share the node SG)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
}

resource "aws_db_instance" "this" {
  for_each = var.environments

  identifier     = "${var.name}-${each.key}"
  engine         = "mysql"
  engine_version = var.mysql_version
  instance_class = each.value.db_instance_class

  allocated_storage     = each.value.db_allocated_storage
  max_allocated_storage = each.value.db_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.env[each.key].arn

  db_name  = "notes"
  username = "notes_admin"

  # RDS creates + stores + (optionally) rotates the master password in
  # Secrets Manager itself. The password never appears in Terraform state
  # or in any file. (The old repo used random_password -> lives in state.)
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.env[each.key].arn

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds[each.key].id]
  publicly_accessible    = false
  multi_az               = each.value.db_multi_az

  backup_retention_period    = each.value.db_backup_retention
  backup_window              = "21:00-22:00" # 02:30-03:30 IST
  maintenance_window         = "sun:22:30-sun:23:30"
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  deletion_protection       = each.value.db_deletion_protection
  skip_final_snapshot       = each.value.db_skip_final_snapshot
  final_snapshot_identifier = each.value.db_skip_final_snapshot ? null : "${var.name}-${each.key}-final"

  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
}
