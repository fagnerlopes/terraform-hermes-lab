# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Idioma: responder e escrever documentação em **português**. Comentários de
código em inglês, como no CloudWeaver.

## O que é

Repositório de workshop: provisiona **uma** VM na Locaweb Cloud (Apache
CloudStack) com o **Hermes Agent** instalado no host. Cada participante do TDC
São Paulo roda na própria máquina, com as próprias credenciais de API.

O público é participante de workshop, não operador de infraestrutura. Toda
decisão de design vale pela pergunta: *isso reduz o número de coisas que podem
dar errado ao vivo, na frente de uma sala?*

## Comandos

Terraform roda sempre dentro do container (`docker compose run --rm -T
terraform`), nunca direto no host. Use o Makefile.

```bash
make up          # caminho completo: setup + chave + init + apply + espera + credenciais
make status      # fase atual da instalação, via SSH
make logs        # tail do /var/log/hermes-lab.log dentro da VM
make down        # destrói tudo e apaga a chave local
make lint        # TFLint (host) + fmt-check + validate (container)
```

Não há testes automatizados. A verificação é `make lint` mais, quando a mudança
toca o cloud-init, o ciclo real `make up` → `make down`.

## Arquitetura

### De onde veio

Três fontes, que valem consulta antes de mudar qualquer coisa:

- **`~/workspaces/workspace-locaweb/repositories/tf-cloud-starter-kit`** — a
  base Terraform (provider, IDs de zona/template, padrão Makefile+Docker).
- **`~/projects/cloud-weaver`** — a receita `hermes-host`, em
  `skills/cloud-weaver-repo-setup/templates/hermes-host/deploy.yml` e
  `docs/superpowers/specs/2026-09-13-hermes-host-recipe-design.md`. O
  `cloud-init.yaml` daqui é aquele pipeline traduzido para cloud-init.
- **`~/workspaces/workspace-locaweb/repositories/vps-recipes`** — receitas
  cloud-init do produto VPS, incluindo uma de Hermes Agent em Docker.

Quando a receita do CloudWeaver mudar, este repo **não** acompanha sozinho.

### Um cenário só

Diferente do `tf-cloud-starter-kit`, aqui não há `cenarioN` nem listas de
`-target` no Makefile: um root module, um state, um `apply` inteiro. Não
reintroduza `-target`.

### O cloud-init é o coração

`cloud-init.yaml` é renderizado por `templatefile()` em `main.tf`. Consequência
que já causou bug: **todo `${...}` no arquivo é interpolado pelo Terraform** —
inclusive dentro de comentários. Variável de shell precisa de `$${...}`.
`$VAR` e `$(cmd)` não são especiais e não precisam de escape.

Antes de commitar mudanças nesse arquivo, renderize e valide:

```bash
echo 'templatefile("cloud-init.yaml", { root_password = "x", sandbox_cpu = 2, sandbox_memory_mb = 4096 })' \
  | docker compose run --rm -T terraform console -var cloudstack_api_key=x -var cloudstack_secret_key=y
```

e confira: YAML válido, `#cloud-config` na coluna 0, nenhum `${` residual, e
`sh -n` limpo no bloco de `runcmd`.

### Decisões que parecem arbitrárias e não são

- **Plano `large` (8 GiB), não `medium`.** A instalação carrega Python, Node e
  Chromium, e o sandbox do terminal reserva `sandbox_memory_mb` (4096) para si.
  Em `medium` (4 GiB) não sobra RAM para o gateway. O spec do CloudWeaver diz
  "medium (4 vCPU / 8 GB)", mas o catálogo real da Locaweb
  (`locaweb-cloud-provision/docs/adr/024-*.md`) define `medium` = 4 GiB e
  `large` = 8 GiB — o spec está mal rotulado.
- **Docker do repositório oficial, nunca snap nem `docker.io`.** O build snap
  quebra os flags `--init` e `no-new-privileges` de que o sandbox do Hermes
  depende. Herdado da receita `hermes-host`.
- **Gateway instalado mas parado.** Sem `TELEGRAM_BOT_TOKEN` em
  `/root/.hermes/.env` ele não tem o que servir. Quem liga é o instrutor,
  ao vivo.
- **Nenhum segredo de LLM ou Telegram no Terraform.** É conteúdo de workshop,
  configurado à mão. Não adicione variáveis para isso sem pedido explícito.
- **Só a porta 22 aberta.** Sem terminal web, sem HTTP. Uma versão anterior do
  desenho usava terminal web com TLS em `<ip>.nip.io`; foi descartada porque
  `nip.io` não está na Public Suffix List, então todos os certificados
  `*.nip.io` do mundo dividem o limite de 50/semana do Let's Encrypt — apostar
  um workshop nisso é temerário.
- **`-T` em todo `docker compose run`.** Sem isso a saída vem com `\r` e as
  comparações de shell no Makefile quebram silenciosamente.

### O contrato de status

`cloud-init.yaml` escreve a fase atual em `/var/lib/hermes-lab/status` e expõe
`/usr/local/bin/hermes-lab-status`. `make up`, `make status` e `make logs`
dependem desses dois caminhos e das strings de fase (`"4/4 pronto"`, prefixo
`"ERRO"`). Mudou a fase, mude o Makefile junto.

O output `credentials` é objeto único consumido via `jq` pelo Makefile — mudar
as chaves dele quebra `make up` e `make credentials`.

## Segurança

- `terraform.tfvars` e `tools/` estão no `.gitignore`. O `setup.sh` grava o
  tfvars com `umask 077` e a chave secreta é lida com `read -s`.
- A validação de credenciais assina a chamada no padrão do CloudStack
  (HMAC-SHA1 sobre a query string ordenada, minúscula e url-encoded). O
  `urlencode` usa `LC_ALL=C` de propósito: em locale UTF-8 o bash fatiaria por
  caractere e produziria assinatura diferente da de qualquer implementação de
  referência.
- A validação **nunca bloqueia** por falha inconclusiva (rede, proxy). Só
  aborta quando a API rejeita explicitamente as chaves.
