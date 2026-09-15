variable "cloudstack_api_key" {
  description = "Chave da API do Locaweb Cloud (painel > Perfil > chaves API)."
  type        = string
  sensitive   = true
}

variable "cloudstack_secret_key" {
  description = "Chave secreta da API do Locaweb Cloud."
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "Nome da VM. Precisa ser único dentro da conta."
  type        = string
  default     = "hermes-lab"

  validation {
    # CloudStack aceita mais do que isso, mas manter o nome restrito evita
    # surpresa no hostname e no DNS interno da rede.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.vm_name))
    error_message = "vm_name deve ter de 3 a 32 caracteres, apenas minúsculas, números e hífen, começando e terminando com letra ou número."
  }
}

variable "service_offering" {
  description = <<-DESC
    Plano de computação da VM. O catálogo da Locaweb vai de `micro` a `4xlarge`.
    `large` (8 GiB) é o padrão porque a instalação do Hermes carrega Python,
    Node e Chromium, e o sandbox de terminal ainda reserva `sandbox_memory_mb`
    para si. Em `medium` (4 GiB) não sobra RAM para o gateway.
  DESC
  type        = string
  default     = "large"
}

variable "sandbox_cpu" {
  description = "vCPUs que o sandbox Docker do terminal do agente pode usar."
  type        = number
  default     = 2
}

variable "sandbox_memory_mb" {
  description = "RAM (MB) do sandbox Docker. Deixe folga para o gateway: em uma VM de 8 GiB, 4096 é o teto saudável."
  type        = number
  default     = 4096
}

variable "ssh_public_key_path" {
  description = "Caminho, dentro do container do Terraform, da chave pública injetada na VM. O Makefile gera o par em tools/ antes do apply."
  type        = string
  default     = "/workspace/tools/hermes_lab_key.pub"
}
