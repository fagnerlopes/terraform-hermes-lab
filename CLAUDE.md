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
- **Senha existe, mas não vale por SSH.** `ssh_pwauth: false` e
  `PermitRootLogin prohibit-password`: a porta 22 fica aberta para a internet e
  senha ali é superfície de força bruta. A senha do `random_password.root`
  continua sendo definida porque o console web do painel (fora da internet
  aberta) não aceita chave — é o resgate de quem perder o `tools/`. Se mexer no
  drop-in de sshd, lembre que ele sobrepõe o `ssh_pwauth` do cloud-init.
- **`CREDENCIAIS.txt` é gerado pelo `make credentials`**, com `umask 077` e
  `chmod 600`, e removido pelo `make down` junto com a chave. Está no
  `.gitignore`; se mudar o nome, mude nos dois lugares.
- **O gateway roda em escopo de USUÁRIO do systemd.** `systemctl list-units`
  não o mostra; é preciso `systemctl --user`. Confirmado numa VM real: o
  `hermes gateway install` do cloud-init instala **e inicia** o serviço, mesmo
  sem token do Telegram. Por isso a instrução ao participante é `hermes gateway
  restart` (para reler o `.env`) e não `start`, que a própria CLI recusa quando
  o serviço está no ar. O `deploy.yml` da receita `hermes-host` do CloudWeaver
  valida com `systemctl is-active --quiet hermes-gateway`, em escopo de
  sistema — lá isso só passa pelo fallback `pgrep`.
- **Nunca declarar `root_disk_size`.** Os planos da Locaweb vêm com disk
  offering fixo (`large` → `d1.large.fixed`, 160 GB). O CloudStack ignora o
  tamanho pedido, cria o da oferta, e o refresh passa a ler um valor diferente
  do declarado. Como o atributo é `ForceNew`, isso recriava a VM **em todo
  apply** — um participante que rodasse `make up` duas vezes perderia a
  máquina. Deixado sem declarar, o atributo é `Computed` e aceita o valor da
  API. O mesmo raciocínio vale para qualquer atributo `optional+computed`:
  confira com `terraform providers schema -json` antes de fixar valor.
- **Firewall depois da instância, não depois do IP.** Uma guest network isolada
  do CloudStack fica em `Allocated` até a primeira VM subir; só então ela é
  implementada e ganha o roteador virtual que aplica as regras. Regra criada
  antes disso falha com `errorcode 530, Failed to create firewall rule`. Isso
  aconteceu de verdade no primeiro apply. Se adicionar portas, mantenha o
  `depends_on` apontando para o port forward.
- **Guard de permissão da chave SSH.** O público roda em Windows + WSL. Em
  `/mnt/c` o WSL ignora `chmod`, a chave sai 0777 e o `ssh` a recusa — o
  laboratório morre esperando a VM. O `ensure-key` confere o `stat` depois do
  `chmod` e aborta com instrução. Não troque essa verificação por heurística de
  caminho: nem todo mount problemático começa com `/mnt`.
- **`.gitattributes` forçando LF.** Clone feito com Git do Windows
  (`core.autocrlf` ligado por padrão) converteria os scripts para CRLF, e um
  `.sh` com CRLF falha como `bad interpreter: /usr/bin/env^M`.
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
