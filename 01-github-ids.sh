#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GH_USER="${GH_USER:-$(gh api user --jq .login)}"
INFRA=notes-lab-infra; APP=notes-app; DEPLOY=notes-app-deploy

mk() { gh repo view "$GH_USER/$1" >/dev/null 2>&1 || gh repo create "$GH_USER/$1" "--$2" >/dev/null; }
mk "$INFRA" public
mk "$APP" private
mk "$DEPLOY" private

OWNER_ID=$(gh api "users/$GH_USER" --jq .id)
INFRA_SUBJECT="$GH_USER@$OWNER_ID/$INFRA@$(gh api "repos/$GH_USER/$INFRA" --jq .id)"
APP_SUBJECT="$GH_USER@$OWNER_ID/$APP@$(gh api "repos/$GH_USER/$APP" --jq .id)"
echo "infra subject: $INFRA_SUBJECT"
echo "app   subject: $APP_SUBJECT"

python3 - <<'PY'
import os
root = "notes-lab-infra"
def rw(path, fn):
    p = os.path.join(root, path)
    if not os.path.exists(p): return
    s = open(p).read(); n = fn(s)
    if n != s: open(p, "w").write(n); print("patched", path)

def boot_main(s):
    if "infra_subject" in s: return s
    s = s.replace("locals {\n  account_id = data.aws_caller_identity.current.account_id\n}",
      'locals {\n  account_id = data.aws_caller_identity.current.account_id\n  infra_subject = var.infra_repo_subject != "" ? var.infra_repo_subject : "${var.github_org}/${var.infra_repo}"\n}')
    return s.replace("repo:${var.github_org}/${var.infra_repo}:", "repo:${local.infra_subject}:")
rw("bootstrap/main.tf", boot_main)

def boot_vars(s):
    if "infra_repo_subject" in s: return s
    return s + '\nvariable "infra_repo_subject" {\n  description = "GitHub token subject of the infra repo"\n  type        = string\n  default     = ""\n}\n'
rw("bootstrap/variables.tf", boot_vars)

def plat_vars(s):
    if "app_repo_subject" in s: return s
    return s + '\nvariable "app_repo_subject" {\n  description = "GitHub token subject of the app repo"\n  type        = string\n  default     = ""\n}\n'
rw("platform/variables.tf", plat_vars)

def plat_ci(s):
    if "app_subject" in s: return s
    s = s.replace("repo:${var.github_org}/${var.app_repo}:", "repo:${local.app_subject}:")
    return 'locals {\n  app_subject = var.app_repo_subject != "" ? var.app_repo_subject : "${var.github_org}/${var.app_repo}"\n}\n\n' + s
rw("platform/github-app-ci.tf", plat_ci)

def wf(s):
    if "TF_VAR_app_repo_subject" in s: return s
    return s.replace("  TF_VAR_github_org: ${{ github.repository_owner }}\n",
      "  TF_VAR_github_org: ${{ github.repository_owner }}\n  TF_VAR_app_repo_subject: ${{ vars.APP_REPO_SUBJECT }}\n")
rw(".github/workflows/_layer.yml", wf)
rw(".github/workflows/destroy.yml", wf)

dbg = os.path.join(root, ".github/workflows/debug-oidc.yml")
if os.path.exists(dbg): os.remove(dbg); print("removed debug-oidc.yml")
PY

TFV=notes-lab-infra/bootstrap/terraform.tfvars
if [ -f "$TFV" ]; then
  grep -v '^infra_repo_subject' "$TFV" > "$TFV.tmp" || true
  echo "infra_repo_subject = \"$INFRA_SUBJECT\"" >> "$TFV.tmp"
  mv "$TFV.tmp" "$TFV"
fi
gh variable set APP_REPO_SUBJECT -R "$GH_USER/$INFRA" --body "$APP_SUBJECT"
command -v terraform >/dev/null && terraform fmt -recursive notes-lab-infra >/dev/null || true
echo "Done. Now run terraform apply in notes-lab-infra/bootstrap."
