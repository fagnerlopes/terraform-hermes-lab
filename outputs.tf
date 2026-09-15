output "public_ip" {
  description = "IP público da VM."
  value       = cloudstack_ipaddress.lab.ip_address
}

output "ssh_command" {
  description = "Comando SSH usando a chave gerada pelo Makefile."
  value       = "ssh -i tools/hermes_lab_key -o StrictHostKeyChecking=no root@${cloudstack_ipaddress.lab.ip_address}"
}

output "root_password" {
  description = "Senha de root, caso a chave SSH não esteja à mão."
  value       = random_password.root.result
  sensitive   = true
}

# Single object consumed by `make credentials` and `make up` through jq.
# Changing its shape breaks those targets.
output "credentials" {
  description = "Dados de acesso à VM."
  sensitive   = true
  value = {
    ip      = cloudstack_ipaddress.lab.ip_address
    usuario = "root"
    senha   = random_password.root.result
    ssh     = "ssh -i tools/hermes_lab_key -o StrictHostKeyChecking=no root@${cloudstack_ipaddress.lab.ip_address}"
  }
}
