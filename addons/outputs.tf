output "argocd_port_forward" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443   # then https://localhost:8080"
}

output "argocd_admin_password" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
