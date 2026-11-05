# Previews por PR (infra/vm/preview.sh). O DNS e o app do Access de cada PR são criados e
# apagados pela VM via API; aqui fica só o que é estático: a policy reutilizável e a metadata.

resource "cloudflare_zero_trust_access_policy" "preview" {
  account_id = var.cloudflare_account_id
  name       = "aurora previews"
  decision   = "allow"
  include    = [for email in var.preview_allowed_emails : { email = { email = email } }]
}

locals {
  preview_metadata = {
    aurora-preview         = file("${path.module}/vm/preview.sh")
    aurora-preview-compose = file("${path.module}/vm/compose.preview.yaml")
    aurora-preview-max     = tostring(var.preview_max)
    aurora-cf-account      = var.cloudflare_account_id
    aurora-cf-zone         = var.cloudflare_zone_id
    aurora-tunnel-cname    = "${cloudflare_zero_trust_tunnel_cloudflared.aurora.id}.cfargotunnel.com"
    aurora-preview-policy  = cloudflare_zero_trust_access_policy.preview.id
  }
}
