#!/usr/bin/env bash
# Run ONCE, from the folder that contains the 3 repo folders.
#   ./00-prepare.sh <your-github-username> <your-email>
# It (1) puts your GitHub username into all files, (2) writes the bootstrap
# settings file, (3) formats + validates all Terraform on your laptop so
# problems show up NOW and not in the pipeline.
set -euo pipefail

GH_USER="${1:?Usage: ./00-prepare.sh <github-username> <your-email>}"
EMAIL="${2:?Usage: ./00-prepare.sh <github-username> <your-email>}"
cd "$(dirname "$0")"

echo "==> 1/3 Writing your GitHub username (${GH_USER}) into the files"
export GH_USER
grep -rlI 'YOUR_ORG' notes-lab-infra notes-app notes-app-deploy | while read -r f; do
  perl -pi -e 's/YOUR_ORG/$ENV{GH_USER}/g' "$f"
done

echo "==> 2/3 Writing notes-lab-infra/bootstrap/terraform.tfvars"
cat > notes-lab-infra/bootstrap/terraform.tfvars <<TFV
state_bucket_name  = "notes-lab-509306733905-tfstate"
github_org         = "${GH_USER}"
budget_email       = "${EMAIL}"
monthly_budget_usd = 100
operator_user_name = "lab-operator"
TFV

echo "==> 3/3 Formatting and validating Terraform"
if ! command -v terraform >/dev/null; then
  echo "!! terraform is not installed yet - install it (Part 0 of the runbook), then run this script again."
  exit 1
fi
terraform fmt -recursive notes-lab-infra >/dev/null
fail=0
for d in bootstrap platform addons; do
  echo "--- $d"
  if terraform -chdir="notes-lab-infra/$d" init -backend=false -input=false -no-color >/tmp/tf-init-$d.log 2>&1 \
     && terraform -chdir="notes-lab-infra/$d" validate -no-color; then
    echo "OK: $d"
  else
    echo "FAILED: $d  (see /tmp/tf-init-$d.log and the message above). Send me the message."
    fail=1
  fi
done
[ "$fail" = 0 ] && echo && echo "All good. Continue with Part 3 of 00-RUNBOOK.md" || exit 1
