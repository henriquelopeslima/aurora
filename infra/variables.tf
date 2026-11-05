variable "project_id" {
  type    = string
  default = "aurora-513810"
}

variable "region" {
  type    = string
  default = "southamerica-east1"
}

variable "zone" {
  type    = string
  default = "southamerica-east1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "domain" {
  description = "Hostname público da aplicação."
  type        = string
  default     = "aurora.henriquelopeslima.dev.br"
}

variable "alert_email" {
  description = "Recebe o alerta do uptime check."
  type        = string
  default     = "henriquelopeslima.hll@gmail.com"
}

variable "github_repository" {
  description = "Único repositório autorizado a fazer deploy (owner/repo)."
  type        = string
  default     = "henriquelopeslima/aurora"
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  description = "Zona henriquelopeslima.dev.br."
  type        = string
}

variable "resend_api_key" {
  description = "API key do Resend (painel do Resend > API Keys)."
  type        = string
  sensitive   = true
}

variable "resend_dkim" {
  description = "Valor TXT do registro resend._domainkey mostrado pelo Resend ao cadastrar o domínio."
  type        = string
}

variable "resend_region" {
  description = "Região do Resend no CNAME de retorno (rsend-<região>.forge.rmta.net); sae1 = São Paulo."
  type        = string
  default     = "sae1"
}

variable "preview_cloudflare_token" {
  description = "Token restrito dos previews (Zone > DNS > Edit na zona, Account > Access: Apps and Policies > Edit). Vai para o Secret Manager e é usado pela VM."
  type        = string
  sensitive   = true
}

variable "preview_max" {
  description = "Máximo de previews no ar ao mesmo tempo (RAM da VM)."
  type        = number
  default     = 2
}

variable "preview_allowed_emails" {
  description = "E-mails que passam pelo Cloudflare Access dos previews."
  type        = list(string)
  default     = ["henriquelopeslima.hll@gmail.com"]
}
