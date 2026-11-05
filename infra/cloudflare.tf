resource "cloudflare_zero_trust_tunnel_cloudflared" "aurora" {
  account_id = var.cloudflare_account_id
  name       = "aurora"
  # Config de ingress vive na Cloudflare (abaixo): o cloudflared sobe só com o token.
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "aurora" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.aurora.id

  config = {
    ingress = [
      {
        hostname = var.domain
        service  = "http://nginx:80" # serviço do compose (infra/vm/compose.yaml)
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "aurora" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.aurora.id
}

resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.aurora.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "aurora - app (tunnel)"
}

# Domínio de envio do Resend = o próprio subdomínio da app, para não tocar e-mail da raiz.
# Registros que o Resend pede para o domínio (painel do Resend > Domains).
resource "cloudflare_dns_record" "resend_send" {
  zone_id = var.cloudflare_zone_id
  name    = "send.${var.domain}"
  type    = "CNAME"
  content = "send.forge.rmta.net"
  proxied = false
  ttl     = 1
  comment = "aurora - Resend (envio)"
}

resource "cloudflare_dns_record" "resend_rsend" {
  zone_id = var.cloudflare_zone_id
  name    = "rsend.${var.domain}"
  type    = "CNAME"
  content = "rsend-${var.resend_region}.forge.rmta.net"
  proxied = false
  ttl     = 1
  comment = "aurora - Resend (retorno)"
}

resource "cloudflare_dns_record" "resend_dkim" {
  zone_id = var.cloudflare_zone_id
  name    = "resend._domainkey.${var.domain}"
  type    = "TXT"
  content = "\"${var.resend_dkim}\""
  ttl     = 1
  comment = "aurora - Resend (DKIM)"
}
