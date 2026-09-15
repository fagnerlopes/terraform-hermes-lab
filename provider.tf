terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "cloudstack" {
  api_url    = "https://painel-cloud.locaweb.com.br/client/api"
  api_key    = var.cloudstack_api_key
  secret_key = var.cloudstack_secret_key
}
