.PHONY: help install setup up up-auto plan-and-confirm down clear credentials status logs ssh plan output lint fmt fmt-check validate ensure-setup ensure-key ensure-init wait-ready

GREEN := \033[0;32m
BLUE  := \033[0;34m
YELLOW:= \033[0;33m
RED   := \033[0;31m
NC    := \033[0m

# -T disables the pseudo-TTY: without it every captured output carries \r and
# breaks the shell comparisons below.
TF := docker compose run --rm -T terraform

KEY        := tools/hermes_lab_key
CREDS_FILE := CREDENCIAIS.txt
# IdentitiesOnly=yes is not optional: -i only ADDS a key to the list, so a
# machine with several keys in ssh-agent offers them all first and the server
# drops the connection at MaxAuthTries ("Too many authentication failures")
# before ever reaching ours.
SSH_OPTS := -i $(KEY) -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR

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
	@PERM=$$(stat -c '%a' $(KEY) 2>/dev/null || stat -f '%Lp' $(KEY) 2>/dev/null); \
	if [ "$$PERM" != "600" ]; then \
		echo ""; \
		echo "$(RED)A chave SSH ficou com permissão $$PERM, e não 600.$(NC)"; \
		echo "$(RED)O ssh vai recusar essa chave e o laboratório não sobe.$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Causa quase certa: o repositório está num disco do Windows$(NC)"; \
		echo "$(YELLOW)(/mnt/c/...), onde o WSL ignora chmod. Diretório atual:$(NC)"; \
		echo "  $(CURDIR)"; \
		echo ""; \
		echo "$(YELLOW)Solução: mova o repositório para dentro do Linux, por exemplo:$(NC)"; \
		echo "  cp -r $(CURDIR) ~/terraform-hermes-lab && cd ~/terraform-hermes-lab"; \
		echo ""; \
		exit 1; \
	fi

ensure-init:
	@if [ ! -d .terraform ]; then \
		echo "$(BLUE)Construindo a imagem do Terraform...$(NC)"; \
		docker compose build; \
		echo "$(BLUE)Inicializando o Terraform...$(NC)"; \
		$(TF) init -input=false; \
	fi

# --------------------------------------------------------------- lifecycle --

up: ## Cria a VM e instala o Hermes, mostrando antes o que será feito (10-20 min)
	@$(MAKE) --no-print-directory ensure-setup
	@$(MAKE) --no-print-directory ensure-key
	@$(MAKE) --no-print-directory ensure-init
	@$(MAKE) --no-print-directory plan-and-confirm
	@echo "$(BLUE)Aplicando...$(NC)"
	@$(TF) apply -input=false tfplan
	@rm -f tfplan
	@$(MAKE) --no-print-directory wait-ready
	@$(MAKE) --no-print-directory credentials

up-auto: ## Igual ao 'up', sem resumo nem confirmação
	@$(MAKE) --no-print-directory up AUTO=1

# Saves the plan to a file and applies exactly that file, so what you approve
# is what runs. Skipped entirely when AUTO is set.
plan-and-confirm:
	@echo "$(BLUE)Verificando o que precisa ser feito...$(NC)"
	@$(TF) plan -input=false -out=tfplan >/dev/null
	@$(TF) show -json tfplan > .tfplan.json 2>/dev/null
	@CREATE=$$(jq -r '[.resource_changes[]? | select(.change.actions|index("create")) | .address] | join(" ")' .tfplan.json); \
	DELETE=$$(jq -r '[.resource_changes[]? | select(.change.actions|index("delete")) | .address] | join(" ")' .tfplan.json); \
	UPDATE=$$(jq -r '[.resource_changes[]? | select(.change.actions == ["update"]) | .address] | join(" ")' .tfplan.json); \
	rm -f .tfplan.json; \
	if [ -z "$$CREATE" ] && [ -z "$$DELETE" ] && [ -z "$$UPDATE" ]; then \
		echo "$(GREEN)Nada a mudar — sua infraestrutura já está como deveria.$(NC)"; \
	else \
		echo ""; \
		[ -n "$$CREATE" ] && { echo "$(GREEN)Vai criar:$(NC)";  for r in $$CREATE; do echo "  + $$r"; done; }; \
		[ -n "$$UPDATE" ] && { echo "$(BLUE)Vai alterar:$(NC)"; for r in $$UPDATE; do echo "  ~ $$r"; done; }; \
		[ -n "$$DELETE" ] && { echo "$(RED)Vai DESTRUIR:$(NC)";  for r in $$DELETE; do echo "  - $$r"; done; }; \
		echo ""; \
		if [ -n "$(AUTO)" ]; then \
			echo "$(YELLOW)AUTO ligado — seguindo sem confirmação.$(NC)"; \
		elif [ -n "$$DELETE" ]; then \
			echo "$(RED)Atenção: isso apaga recursos que já existem.$(NC)"; \
			echo "$(RED)Se a VM está na lista, você perde o que estiver dentro dela.$(NC)"; \
			printf "Digite 'sim' para confirmar: "; read ans; \
			if [ "$$ans" != "sim" ]; then rm -f tfplan; echo "$(YELLOW)Cancelado. Nada foi alterado.$(NC)"; exit 1; fi; \
		else \
			printf "Continuar? (s/N) "; read ans; \
			case "$$ans" in [sS]*) ;; *) rm -f tfplan; echo "$(YELLOW)Cancelado. Nada foi alterado.$(NC)"; exit 1 ;; esac; \
		fi; \
	fi

wait-ready:
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(RED)Não consegui obter o IP. Rode 'make output'.$(NC)"; exit 1; fi; \
	echo ""; \
	INITIAL=$$(ssh $(SSH_OPTS) root@$$IP 'hermes-lab-status' 2>/dev/null | tr -d '\r'); \
	if [ "$$INITIAL" = "4/4 pronto" ]; then \
		echo "$(GREEN)A VM em $$IP já está no ar, com o Hermes instalado.$(NC)"; \
		echo "$(GREEN)Nada foi recriado — nenhuma espera necessária.$(NC)"; \
		exit 0; \
	fi; \
	echo "$(BLUE)VM em $$IP. Instalando o Hermes Agent — isso leva de 10 a 20 minutos.$(NC)"; \
	echo "$(YELLOW)Pode deixar rodando; o progresso aparece abaixo.$(NC)"; \
	echo ""; \
	DONE=0; \
	for i in $$(seq 1 300); do \
		STATUS=$$(ssh $(SSH_OPTS) root@$$IP 'hermes-lab-status' 2>/dev/null | tr -d '\r'); \
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

down: ## Destrói a VM e apaga a chave SSH e o CREDENCIAIS.txt
	@echo "$(YELLOW)Destruindo o laboratório...$(NC)"
	@$(TF) destroy -auto-approve -refresh=false -input=false
	@rm -f $(KEY) $(KEY).pub $(CREDS_FILE)
	@echo "$(GREEN)Laboratório destruído.$(NC)"

clear: ## Apaga suas credenciais desta máquina (antes de sair de um computador emprestado)
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)  Limpando suas credenciais desta máquina$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "Serão apagados desta pasta:"
	@for f in terraform.tfvars terraform.tfstate terraform.tfstate.backup $(CREDS_FILE) tfplan .tfplan.json; do \
		[ -e "$$f" ] && echo "  - $$f" || true; \
	done
	@[ -d tools ] && echo "  - tools/ (sua chave SSH)" || true
	@echo ""
	@RESOURCES=$$($(TF) state list </dev/null 2>/dev/null | tr -d '\r' | grep -c . || true); \
	if [ "$$RESOURCES" -gt 0 ] 2>/dev/null; then \
		echo "$(RED)Atenção: seu laboratório ainda está NO AR.$(NC)"; \
		echo ""; \
		echo "$(YELLOW)O state também vai embora, e com ele o 'make down': depois disso a$(NC)"; \
		echo "$(YELLOW)única forma de destruir a VM é pelo painel da Locaweb.$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Quer continuar usando a VM depois? Leve o $(CREDS_FILE) com você:$(NC)"; \
		echo "$(YELLOW)com a senha dele dá para entrar pelo console web do painel,$(NC)"; \
		echo "$(YELLOW)mesmo sem a chave SSH.$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Prefere destruir tudo agora? Cancele e rode 'make down'.$(NC)"; \
		echo ""; \
	fi; \
	printf "Digite 'sim' para apagar: "; read ans; \
	if [ "$$ans" != "sim" ]; then echo "$(YELLOW)Cancelado. Nada foi apagado.$(NC)"; exit 1; fi
	@rm -rf terraform.tfvars terraform.tfstate terraform.tfstate.backup $(CREDS_FILE) tfplan .tfplan.json tools
	@echo ""
	@echo "$(GREEN)Pronto. Nenhuma credencial sua ficou nesta máquina.$(NC)"
	@echo "$(BLUE)Os providers baixados (.terraform/) continuam aqui — não são seus$(NC)"
	@echo "$(BLUE)dados, e poupam o download de quem usar esta máquina depois.$(NC)"

# ------------------------------------------------------------------- acesso --

credentials: ## Mostra IP e senha, e grava o CREDENCIAIS.txt
	@CREDS=$$($(TF) output -json credentials 2>/dev/null | tr -d '\r'); \
	if [ -z "$$CREDS" ] || [ "$$CREDS" = "null" ]; then \
		echo "$(YELLOW)Sem dados ainda. Rode 'make up' primeiro.$(NC)"; exit 0; \
	fi; \
	umask 077; \
	echo "$$CREDS" | jq -r '"Laboratório Hermes — TDC São Paulo", "==================================", "", "IP público: " + .ip, "Usuário:    " + .usuario, "Senha:      " + .senha, "", "Entrar por SSH (use sempre este caminho):", "  " + .ssh, "", "A senha NÃO funciona por SSH — o acesso remoto é só por chave.", "Ela serve no console web do painel, caso você perca a chave:", "  https://painel-cloud.locaweb.com.br", "", "O cupom do TDC cobre este laboratório durante o evento e por 30 dias.", "Aproveite. Quando terminar de experimentar, desligue com:", "  make down", "", "Guarde este arquivo antes de ir embora: ele não é recuperável", "depois que a VM for destruída."' > $(CREDS_FILE); \
	chmod 600 $(CREDS_FILE); \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(BLUE)  Seu laboratório Hermes$(NC)"; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$$CREDS" | jq -r '"", "  IP:      " + .ip, "  Usuário: " + .usuario, "  Senha:   " + .senha, "", "  Entrar:  " + .ssh, ""'; \
	echo "$(GREEN)  Já dentro da VM, o próximo passo é:$(NC)"; \
	echo "    hermes setup"; \
	echo ""; \
	echo "$(YELLOW)  A senha não funciona por SSH — só no console web do painel.$(NC)"; \
	echo "$(GREEN)  Salvo também em $(CREDS_FILE) (não versionado). Leve com você.$(NC)"; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"

ssh: ## Abre uma sessão SSH na VM
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(YELLOW)Lab não provisionado. Rode 'make up'.$(NC)"; exit 1; fi; \
	ssh $(SSH_OPTS) root@$$IP || true   # exit code of an interactive shell is not a make failure

status: ## Mostra em que fase está a instalação
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(YELLOW)Lab não provisionado. Rode 'make up'.$(NC)"; exit 1; fi; \
	echo "$(BLUE)Fase:$(NC) $$(ssh $(SSH_OPTS) root@$$IP 'hermes-lab-status' 2>/dev/null || echo 'sem resposta no SSH')"

logs: ## Acompanha o log da instalação na VM
	@IP=$$($(TF) output -raw public_ip 2>/dev/null | tr -d '\r'); \
	if [ -z "$$IP" ]; then echo "$(YELLOW)Lab não provisionado. Rode 'make up'.$(NC)"; exit 1; fi; \
	ssh $(SSH_OPTS) root@$$IP 'tail -f -n 200 /var/log/hermes-lab.log' || true   # Ctrl-C on the tail is not a make failure

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
