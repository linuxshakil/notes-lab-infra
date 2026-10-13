# Copy to backend.tf AFTER the first apply, then run:
#   terraform init -migrate-state -force-copy
# so that bootstrap's own state also lives in the (versioned, encrypted) S3 bucket.
terraform {
  backend "s3" {
    bucket       = "notes-lab-509306733905-tfstate"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
