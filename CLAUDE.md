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
- **`https://cofounder.locaweb.com.br/install.sh`** — o instalador do
  Cofounder. A fase `4/5` do cloud-init espelha a metade "máquina" dele.

Quando a receita do CloudWeaver ou o instalador do Cofounder mudarem, este repo
**não** acompanha sozinho.

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
- **Todo comando SSH leva `IdentitiesOnly=yes`.** O `-i` não restringe as
  chaves oferecidas, apenas acrescenta uma à lista: numa máquina com várias
  chaves no `ssh-agent`, o cliente oferece todas antes da nossa, o servidor
  corta em `MaxAuthTries` e a conexão morre com "Too many authentication
  failures". Aconteceu de verdade. O `-i` mora dentro do `SSH_OPTS` para que
  nenhum alvo novo esqueça — e o mesmo vale para o comando gravado no
  CREDENCIAIS.txt, via output `credentials`.
- **Todo comando SSH publicado leva `UserKnownHostsFile=/dev/null`.** A Locaweb
  recicla IPs: destruir e recriar o lab costuma devolver o mesmo endereço com
  outra host key, e aí o `known_hosts` do participante faz o `ssh` recusar com
  `REMOTE HOST IDENTIFICATION HAS CHANGED`. `StrictHostKeyChecking=no` não
  cobre esse caso — ele só aceita chave nova, não chave alterada. Observado na
  prática. Vale para o `SSH_OPTS` do Makefile e para o comando gravado no
  output `credentials`, que vai parar no CREDENCIAIS.txt.
- **Senha existe, mas não vale por SSH.** `ssh_pwauth: false` e
  `PermitRootLogin prohibit-password`: a porta 22 fica aberta para a internet e
  senha ali é superfície de força bruta. A senha do `random_password.root`
  continua sendo definida porque o console web do painel (fora da internet
  aberta) não aceita chave — é o resgate de quem perder o `tools/`. Se mexer no
  drop-in de sshd, lembre que ele sobrepõe o `ssh_pwauth` do cloud-init.
- **Chave SSH perdida com a VM no ar é caso sem volta pelo Terraform.** O
  CloudStack só lê o keypair no momento em que a instância é criada: trocar o
  `cloudstack_ssh_keypair` depois disso replaca o objeto na API e não encosta
  no `authorized_keys` da VM que já roda (o plano mostra `keypair` replaced e
  a instância só com `user_data` in-place). Por isso `up` tem o guard
  `ensure-key-usable` — sem ele o `make up` geraria chave nova e ficaria 25
  minutos no `wait-ready` esperando um SSH que nunca autentica — e `ssh`,
  `status` e `logs` passam por `require-key`, que explica o resgate (console
  web do painel com a senha do `CREDENCIAIS.txt`) em vez de deixar o ssh
  responder só `Permission denied (publickey)`. O `-i` com
  `IdentitiesOnly=yes` não oferece chave nenhuma quando o arquivo não existe.
  Corolário para quem mexe aqui: `tools/` é credencial viva, não artefato de
  teste, e é gitignored — apagá-lo não limpa nada no `git status` e tranca o
  dono da VM do lado de fora. Já aconteceu, com o laboratório no ar.
- **`make clear` apaga credenciais; `make down` destrói infraestrutura.** São
  coisas diferentes e os nomes são parecidos — não unifique. Existia também um
  `make clean` (alias de `down` + cleanup do Docker); foi **removido** porque
  ficava a uma letra do `clear` e destruía a VM sem perguntar nada. Não
  reintroduza nenhum alvo cujo nome se pareça com `clear` e que seja
  destrutivo. O `clear` remove
  `terraform.tfvars`, `terraform.tfstate*`, `CREDENCIAIS.txt`, `tools/` e os
  arquivos de plano, mantendo `.terraform/` (providers não são dados de
  ninguém e o download é caro numa rede de evento). O state entra na lista
  porque guarda o `random_password` em texto puro — é credencial, não só
  registro.
- **Nunca ponha um `docker compose run` na mesma linha de receita que um
  `read`.** Ele consome o stdin e a confirmação nunca chega: o `read` recebe
  vazio e o comando se comporta como cancelado. Aconteceu no `clear`; a solução
  é `</dev/null` na chamada do Terraform.
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
- **A fase `4/5` espelha o instalador do Cofounder, e nunca é fatal.** Ela
  pré-instala `podman`, `mise`, `gh`, os toolchains `node@lts`/`node@24` e as
  bibliotecas do Chromium nos mesmos alvos que o `install.sh` usa, para cair nas
  guardas de idempotência dele (`have podman`, o canário `libnspr4`/`libnss3` no
  `ldconfig`, a linha de PATH no `~/.bashrc` — que é comparada com `grep -qsxF`,
  então precisa bater byte a byte, ou o instalador acrescenta uma segunda). Todo
  passo termina em `|| warn`, nunca em `fail`: o Cofounder é acelerador, o
  laboratório é o Hermes, e um repo do `gh` fora do ar no meio do evento não
  pode impedir a VM de chegar em `5/5 pronto`. O bloco exporta `HOME=/root`
  explicitamente — o cloud-init não garante `HOME`, e tanto o `mise.run` quanto
  a linha de PATH resolvem o destino a partir dele. E `podman`, nunca
  `podman-docker`: esse pacote instala um shim em `/var/run/docker.sock` que
  brigaria com o Docker Engine do sandbox do Hermes.
- **`-T` em todo `docker compose run`.** Sem isso a saída vem com `\r` e as
  comparações de shell no Makefile quebram silenciosamente.

### O contrato de status

`cloud-init.yaml` escreve a fase atual em `/var/lib/hermes-lab/status` e expõe
`/usr/local/bin/hermes-lab-status`. `make up`, `make status` e `make logs`
dependem desses dois caminhos e das strings de fase (`"5/5 pronto"`, prefixo
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
