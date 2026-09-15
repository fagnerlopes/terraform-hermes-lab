.PHONY: help install setup up down credentials status logs ssh plan output lint fmt fmt-check validate clean ensure-setup ensure-key ensure-init wait-ready

GREEN := \033[0;32m
BLUE  := \033[0;34m
YELLOW:= \033[0;33m
RED   := \033[0;31m
NC    := \033[0m

# -T disables the pseudo-TTY: without it every captured output carries \r and
# breaks the shell comparisons below.
TF := docker compose run --rm -T terraform

KEY      := tools/hermes_lab_key
SSH_OPTS := -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR

help: ## Mostra os comandos disponíveis
	@echo "$(BLUE)Laboratório Hermes — TDC São Paulo$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-14s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Começando do zero?  $(BLUE)make up$(NC)  cuida de tudo."

install: ## Prepara o ambiente (imagem Docker + terraform init)
	@$(MAKE) --no-print-directory ensure-init

setup: ## Coleta e valida as credenciais, gerando o terraform.tfvars
	@./scripts/setup.sh

# ------------------------------------------------------------------ guards --

ensure-setup:
	@if [ ! -f terraform.tfvars ]; then \
		echo "$(YELLOW)Nenhum terraform.tfvars encontrado — vamos criar um.$(NC)"; echo ""; \
		./scripts/setup.sh; echo ""; \
	fi

ensure-key:
	@mkdir -p tools
	@if [ ! -f $(KEY) ]; then \
		echo "$(BLUE)Gerando chave SSH do laboratório ($(KEY))...$(NC)"; \
		ssh-keygen -t ed25519 -N '' -f $(KEY) -q -C "hermes-lab"; \
	fi
	@chmod 600 $(KEY)

ensure-init:
	@if [ ! -d .terraform ]; then \
		echo "$(BLUE)Construindo a imagem do Terraform...$(NC)"; \
		docker compose build; \
		echo "$(BLUE)Inicializando o Terraform...$(NC)"; \
		$(TF) init -input=false; \
	fi

# --------------------------------------------------------------- lifecycle --

up: ## Cria a VM e instala o Hermes (de 10 a 20 minutos)
	@$(MAKE) --no-print-directory ensure-setup
	@$(MAKE) --no-print-directory ensure-key
	@$(MAKE) --no-print-directory ensure-init
	@echo "$(BLUE)Provisionando a VM na Locaweb Cloud...$(NC)"
	@$(TF) apply -auto-approve -input=false
	@$(MAKE) --no-print-directory wait-ready
	@$(MAKE) --no-print-directory credentials

wait-ready:
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(RED)Não consegui obter o IP. Rode 'make output'.$(NC)"; exit 1; fi; \
	echo ""; \
	echo "$(BLUE)VM criada em $$IP. Instalando o Hermes Agent — isso leva de 10 a 20 minutos.$(NC)"; \
	echo "$(YELLOW)Pode deixar rodando; o progresso aparece abaixo.$(NC)"; \
	echo ""; \
	DONE=0; \
	for i in $$(seq 1 300); do \
		STATUS=$$(ssh -i $(KEY) $(SSH_OPTS) root@$$IP 'hermes-lab-status' 2>/dev/null | tr -d '\r'); \
		[ -z "$$STATUS" ] && STATUS="aguardando a VM responder ao SSH"; \
		case "$$STATUS" in \
			ERRO*) echo ""; echo "$(RED)$$STATUS$(NC)"; \
				echo "$(YELLOW)Veja o log completo com: make logs$(NC)"; exit 1 ;; \
			"4/4 pronto") DONE=1 ;; \
		esac; \
		[ $$DONE -eq 1 ] && break; \
		printf "  $(YELLOW)[%3d/300]$(NC) %-55s\r" $$i "$$STATUS"; \
		sleep 5; \
	done; \
	printf "%-75s\r" " "; \
	if [ $$DONE -eq 1 ]; then \
		echo "$(GREEN)Hermes Agent instalado e pronto.$(NC)"; \
	else \
		echo "$(YELLOW)Tempo esgotado. A instalação pode ainda estar rodando.$(NC)"; \
		echo "$(YELLOW)Acompanhe com: make status   (ou make logs)$(NC)"; \
	fi

down: ## Destrói a VM e apaga a chave SSH local
	@echo "$(YELLOW)Destruindo o laboratório...$(NC)"
	@$(TF) destroy -auto-approve -refresh=false -input=false
	@rm -f $(KEY) $(KEY).pub
	@echo "$(GREEN)Laboratório destruído.$(NC)"

clean: down ## Alias de 'down', mais o cleanup dos recursos do Docker
	@docker compose down -v --remove-orphans 2>/dev/null || true

# ------------------------------------------------------------------- acesso --

credentials: ## Mostra IP, senha e o comando de acesso
	@CREDS=$$($(TF) output -json credentials 2>/dev/null | tr -d '\r'); \
	if [ -z "$$CREDS" ] || [ "$$CREDS" = "null" ]; then \
		echo "$(YELLOW)Sem dados ainda. Rode 'make up' primeiro.$(NC)"; exit 0; \
	fi; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(BLUE)  Seu laboratório Hermes$(NC)"; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$$CREDS" | jq -r '"", "  IP:      " + .ip, "  Usuário: " + .usuario, "  Senha:   " + .senha, "", "  Entrar:  " + .ssh, ""'; \
	echo "$(GREEN)  Já dentro da VM, o próximo passo é:$(NC)"; \
	echo "    hermes setup"; \
	echo ""; \
	echo "$(YELLOW)  A senha acima não é recuperável depois que o lab for destruído.$(NC)"; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"

ssh: ## Abre uma sessão SSH na VM
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(YELLOW)Lab não provisionado. Rode 'make up'.$(NC)"; exit 1; fi; \
	ssh -i $(KEY) $(SSH_OPTS) root@$$IP

status: ## Mostra em que fase está a instalação
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(YELLOW)Lab não provisionado. Rode 'make up'.$(NC)"; exit 1; fi; \
	echo "$(BLUE)Fase:$(NC) $$(ssh -i $(KEY) $(SSH_OPTS) root@$$IP 'hermes-lab-status' 2>/dev/null || echo 'sem resposta no SSH')"

logs: ## Acompanha o log da instalação na VM
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(YELLOW)Lab não provisionado. Rode 'make up'.$(NC)"; exit 1; fi; \
	ssh -i $(KEY) $(SSH_OPTS) root@$$IP 'tail -f -n 200 /var/log/hermes-lab.log'

# ----------------------------------------------------------------- terraform -

plan: ## Mostra o plano do Terraform
	@$(TF) plan

output: ## Mostra todos os outputs
	@$(TF) output

validate: ## Valida a configuração
	@$(TF) validate

fmt: ## Formata os arquivos .tf
	@$(TF) fmt -recursive

fmt-check: ## Confere a formatação sem alterar nada
	@$(TF) fmt -check -recursive

lint: ## Roda todas as verificações de qualidade
	@echo "$(BLUE)1/3 TFLint$(NC)"
	@if command -v tflint >/dev/null 2>&1; then \
		tflint; \
	else \
		echo "$(YELLOW)TFLint não instalado no host — rodando via container.$(NC)"; \
		docker run --rm -v "$$PWD:/data" ghcr.io/terraform-linters/tflint:latest --chdir=/data; \
	fi
	@echo "$(BLUE)2/3 Formatação$(NC)"
	@$(MAKE) --no-print-directory fmt-check
	@echo "$(BLUE)3/3 Validação$(NC)"
	@$(MAKE) --no-print-directory validate
	@echo "$(GREEN)Tudo certo.$(NC)"
