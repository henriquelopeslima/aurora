output "registry" {
  description = "Prefixo das imagens (REGISTRY no compose)."
  value       = local.registry
}

output "instance_name" {
  value = google_compute_instance.aurora.name
}

output "ssh_command" {
  description = "Acesso de diagnóstico, via IAP."
  value       = "gcloud compute ssh ${google_compute_instance.aurora.name} --zone ${var.zone} --tunnel-through-iap"
}
