variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "state_bucket" {
  description = "The Terraform state bucket created by bootstrap"
  type        = string
}

variable "deploy_repo_url" {
  description = "HTTPS URL of the notes-app-deploy repo that ArgoCD watches"
  type        = string
}

variable "deploy_repo_revision" {
  type    = string
  default = "main"
}
