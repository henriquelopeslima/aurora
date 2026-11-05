resource "google_artifact_registry_repository" "aurora" {
  repository_id = "aurora"
  location      = var.region
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

locals {
  registry = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.aurora.repository_id}"
}
