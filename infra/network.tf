# Rede própria: a "default" nasce com SSH/RDP abertos para 0.0.0.0/0.
resource "google_compute_network" "aurora" {
  name                    = "aurora"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "aurora" {
  name          = "aurora"
  network       = google_compute_network.aurora.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/24"
}

# Única entrada: SSH vindo do IAP. A app chega pelo Cloudflare Tunnel (conexão de saída).
resource "google_compute_firewall" "iap_ssh" {
  name          = "aurora-allow-iap-ssh"
  network       = google_compute_network.aurora.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["aurora"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
