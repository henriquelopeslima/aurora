output "registry" {
  description = "Prefixo das imagens (REGISTRY no compose)."
  value       = local.registry
}

output "instance_name" {
  value = google_compute_instance.aurora.name
}

output "GCP_WIF_PROVIDER" {
  description = "Variable do repositório no GitHub (gh variable set GCP_WIF_PROVIDER)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "GCP_DEPLOY_SA" {
  description = "Variable do repositório no GitHub (gh variable set GCP_DEPLOY_SA)."
  value       = google_service_account.deploy.email
}

output "ssh_command" {
  description = "Acesso de diagnóstico, via IAP."
  value       = "gcloud compute ssh ${google_compute_instance.aurora.name} --zone ${var.zone} --tunnel-through-iap"
}
