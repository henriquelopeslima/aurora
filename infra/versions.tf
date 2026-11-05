terraform {
  required_version = ">= 1.8"

  # Bucket criado no bootstrap (ver README); backend não aceita variáveis.
  backend "gcs" {
    bucket = "aurora-513810-tfstate"
    prefix = "aurora"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Token via variável de ambiente CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}
