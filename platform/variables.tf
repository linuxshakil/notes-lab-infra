variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "name" {
  description = "Project / cluster name (prefix for everything)"
  type        = string
  default     = "notes-lab"
}

variable "github_org" {
  type = string
}

variable "app_repo" {
  description = "GitHub repo name of the application (builds + pushes the image)"
  type        = string
  default     = "notes-app"
}

variable "kubernetes_version" {
  description = "EKS version. Check `aws eks describe-cluster-versions` and pick a version that is still in STANDARD support (extended support is billed extra)."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one NAT (cheap, one AZ is a SPOF). false = one NAT per AZ (production)."
  type        = bool
  default     = true
}

variable "api_public_access_cidrs" {
  description = "Who may reach the EKS API endpoint (IAM auth is still required). GitHub-hosted runners have no fixed IPs, so default is open. Production hardening: private endpoint + self-hosted runner."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "mysql_version" {
  description = "RDS MySQL major.minor. 8.0 is out of standard support on RDS (extended support = extra $), so default is 8.4."
  type        = string
  default     = "8.4"
}

# One entry per namespace/environment. Everything below (RDS, bucket,
# KMS key, IAM role) is created once per entry via for_each.
variable "environments" {
  type = map(object({
    db_instance_class      = string
    db_allocated_storage   = number
    db_multi_az            = bool
    db_backup_retention    = number
    db_deletion_protection = bool
    db_skip_final_snapshot = bool
  }))

  default = {
    dev = {
      db_instance_class      = "db.t4g.micro"
      db_allocated_storage   = 20
      db_multi_az            = false
      db_backup_retention    = 1
      db_deletion_protection = false
      db_skip_final_snapshot = true
    }
    test = {
      db_instance_class      = "db.t4g.micro"
      db_allocated_storage   = 20
      db_multi_az            = false
      db_backup_retention    = 1
      db_deletion_protection = false
      db_skip_final_snapshot = true
    }
    prod = {
      db_instance_class      = "db.t4g.micro"
      db_allocated_storage   = 20
      db_multi_az            = false # flip to true when you want real HA (doubles DB cost)
      db_backup_retention    = 1
      db_deletion_protection = true
      db_skip_final_snapshot = false
    }
  }
}

variable "app_repo_subject" {
  description = "GitHub token subject of the app repo"
  type        = string
  default     = ""
}
