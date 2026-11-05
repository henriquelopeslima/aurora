resource "google_artifact_registry_repository" "aurora" {
  repository_id = "aurora"
  location      = var.region
  format        = "DOCKER"

  # Só previews expiram; as tags de prod continuam disponíveis para rollback.
  cleanup_policies {
    id     = "drop-old-previews"
    action = "DELETE"
    condition {
      tag_state             = "ANY"
      package_name_prefixes = ["php-preview"]
      older_than            = "604800s"
    }
  }

  depends_on = [google_project_service.apis]
}

locals {
  registry = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.aurora.repository_id}"
}
