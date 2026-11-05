# Segredos gerados aqui ficam também no state (bucket privado e versionado).

resource "random_password" "postgres" {
  length  = 32
  special = false # vai dentro da DATABASE_URL
}

resource "random_password" "mongo" {
  length  = 32
  special = false # vai dentro da MONGODB_URL
}

resource "random_id" "app_secret" {
  byte_length = 16
}

# Par JWT sem passphrase (JWT_PASSPHRASE vazio no compose).
resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  # Nome no Secret Manager => valor. Os nomes são o contrato com infra/vm/deploy.sh.
  secrets = {
    "aurora-app-secret"        = random_id.app_secret.hex
    "aurora-postgres-password" = random_password.postgres.result
    "aurora-mongo-password"    = random_password.mongo.result
    "aurora-mailer-dsn"        = "smtp://resend:${var.resend_api_key}@smtp.resend.com:587"
    "aurora-tunnel-token"      = data.cloudflare_zero_trust_tunnel_cloudflared_token.aurora.token
    "aurora-jwt-private-key"   = tls_private_key.jwt.private_key_pem
    "aurora-jwt-public-key"    = tls_private_key.jwt.public_key_pem
  }
}

# Nomes estáticos: as chaves de local.secrets ficam desconhecidas no plan enquanto o
# tunnel não existe (o token vem de um data source), e for_each exige chaves conhecidas.
locals {
  secret_names = toset([
    "aurora-app-secret",
    "aurora-postgres-password",
    "aurora-mongo-password",
    "aurora-mailer-dsn",
    "aurora-tunnel-token",
    "aurora-jwt-private-key",
    "aurora-jwt-public-key",
  ])
}

resource "google_secret_manager_secret" "app" {
  for_each  = local.secret_names
  secret_id = each.value

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "app" {
  for_each    = local.secret_names
  secret      = google_secret_manager_secret.app[each.key].id
  secret_data = local.secrets[each.key]
}

locals {
  secret_ids = { for name in local.secret_names : name => google_secret_manager_secret.app[name].id }
}
