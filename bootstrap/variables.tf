variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "name" {
  description = "Project name, used as a prefix for resources"
  type        = string
  default     = "notes-lab"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state, e.g. notes-lab-123456789012-tfstate"
  type        = string
}

variable "github_org" {
  description = "GitHub user or organisation that owns the repos"
  type        = string
}

variable "infra_repo" {
  description = "Name (not URL) of THIS repository on GitHub"
  type        = string
  default     = "notes-lab-infra"
}

variable "budget_email" {
  description = "Email that receives budget alerts"
  type        = string
}

variable "monthly_budget_usd" {
  type    = number
  default = 300
}

variable "operator_user_name" {
  description = "The IAM user a human logs in with (created by hand in the console, see runbook). It gets NO permissions except: assume the admin/readonly role with MFA."
  type        = string
  default     = "lab-operator"
}

variable "enable_guardduty" {
  description = "Threat detection. First 30 days free, then a few dollars per month for a small account."
  type        = bool
  default     = true
}

variable "infra_repo_subject" {
  description = "GitHub token subject of the infra repo"
  type        = string
  default     = ""
}
