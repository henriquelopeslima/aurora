resource "google_service_account" "vm" {
  account_id   = "aurora-vm"
  display_name = "aurora VM"

  depends_on = [google_project_service.apis]
}

resource "google_artifact_registry_repository_iam_member" "vm_reader" {
  location   = google_artifact_registry_repository.aurora.location
  repository = google_artifact_registry_repository.aurora.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_secret_manager_secret_iam_member" "vm" {
  for_each  = local.secret_ids
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm" {
  for_each = toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.vm.email}"
}

# Bancos e uploads. Sobrevive à VM; para destruir, remova o prevent_destroy de propósito.
resource "google_compute_disk" "data" {
  name = "aurora-data"
  type = "pd-balanced"
  size = 20
  zone = var.zone

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.apis]
}

resource "google_compute_resource_policy" "daily" {
  name   = "aurora-daily-snapshot"
  region = var.region

  depends_on = [google_project_service.apis]

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "06:00" # UTC = 03:00 em Brasília
      }
    }
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      storage_locations = [var.region]
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "daily" {
  name = google_compute_resource_policy.daily.name
  disk = google_compute_disk.data.name
  zone = var.zone
}

resource "google_compute_instance" "aurora" {
  name         = "aurora"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["aurora"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "aurora-data" # vira /dev/disk/by-id/google-aurora-data
  }

  network_interface {
    subnetwork = google_compute_subnetwork.aurora.id
    # IP efêmero só para saída (imagens, Resend, tunnel); a entrada segue fechada pelo firewall.
    # Cloud NAT custaria mais que a própria VM.
    access_config {}
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin  = "TRUE"
    startup-script  = file("${path.module}/vm/startup.sh")
    aurora-deploy   = file("${path.module}/vm/deploy.sh")
    aurora-compose  = file("${path.module}/vm/compose.yaml")
    aurora-registry = local.registry
  }

  allow_stopping_for_update = true

  # No boot de uma VM recriada o deploy já precisa ler segredos e imagens.
  depends_on = [
    google_secret_manager_secret_iam_member.vm,
    google_artifact_registry_repository_iam_member.vm_reader,
    google_secret_manager_secret_version.app,
  ]
}
