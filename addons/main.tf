############################################################
# Cluster add-ons. Terraform installs only the *platform*
# controllers. Applications are NOT deployed from here — that is
# ArgoCD's job (GitOps).
#
# Chart versions are pinned. If a pinned version has been pulled,
# run `helm search repo <chart> --versions` and bump it.
############################################################

# --- AWS Load Balancer Controller: turns Ingress into an ALB ---
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.13.0"

  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName = local.p.cluster_name
    region      = var.region
    vpcId       = local.p.vpc_id
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.p.alb_controller_role_arn
      }
    }
  })]
}

# --- metrics-server: needed by HorizontalPodAutoscaler ---
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"

  wait = true
}

# --- External Secrets Operator: AWS Secrets Manager -> k8s Secret ---
# The operator itself needs NO AWS permissions. Each namespace has its own
# SecretStore that authenticates as that namespace's ServiceAccount (IRSA),
# so "dev" can only ever read dev's secret.
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.19.2"

  wait    = true
  timeout = 600

  values = [yamlencode({
    installCRDs = true
  })]
}

# --- ArgoCD ---
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"

  wait    = true
  timeout = 600

  values = [yamlencode({
    configs = {
      rbac = {
        # Anyone who logs in and has no explicit role can only look.
        "policy.default" = "role:readonly"
      }
    }
    server = {
      service = { type = "ClusterIP" } # reach the UI with kubectl port-forward
    }
  })]

  depends_on = [
    helm_release.alb_controller,
    helm_release.external_secrets,
    helm_release.metrics_server,
  ]
}

# --- The single "root" Application. It points at argocd/bootstrap in the
#     deploy repo, which in turn contains the AppProjects and the
#     ApplicationSet that creates notes-app-dev / -test / -prod.
#     (argocd-apps chart 2.x: `applications` is a map.)
resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = "argocd"
  version    = "2.0.2"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.deploy_repo_url
          targetRevision = var.deploy_repo_revision
          path           = "argocd/bootstrap"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
