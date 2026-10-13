# notes-lab-infra

Terraform for the whole platform. Three layers, three state files in one S3 bucket:

| Layer | Run by | Contains |
|---|---|---|
| `bootstrap/` | you, once, from your laptop (MFA login) | state bucket, GitHub OIDC + plan/apply roles, human roles (MFA), CloudTrail, budget, account guard-rails |
| `platform/` | GitHub Actions | VPC, EKS, per env (dev/test/prod): RDS MySQL, S3 bucket, KMS key, IRSA role; ECR; app-CI role |
| `addons/` | GitHub Actions | ALB controller, metrics-server, External Secrets, ArgoCD + root app |

Pipeline: PR -> fmt / validate / plan (read-only role). Merge to `main` -> plan -> **manual approval**
(GitHub Environment `production-infra`) -> apply the same plan file.

Add or remove an environment: edit the `environments` map in `platform/variables.tf`.

Step-by-step guide: `../00-RUNBOOK.md`
