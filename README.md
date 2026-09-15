# Laboratório Hermes — TDC São Paulo

Sobe uma VM na **Locaweb Cloud** com o **Hermes Agent** já instalado, pronta
para o workshop. Você roda um comando, espera, e entra na máquina por SSH.

A configuração do agente (provedor de LLM, GitHub, Telegram) **não** é feita
aqui: fazemos isso juntos, ao vivo, no workshop.

---

## Antes de começar

Você precisa de:

1. **Uma conta na Locaweb Cloud** com chaves de API. Como gerar:
   - acesse <https://painel-cloud.locaweb.com.br>
   - clique no seu nome (canto superior direito) → **Perfil**
   - clique em **Gerar novas chaves API/Secretas**
   - deixe a aba aberta — você vai colar as duas chaves daqui a pouco

2. **Linux, WSL (Windows) ou macOS** com estes programas instalados:

   ```bash
   sudo apt-get update
   sudo apt-get install -y make jq openssh-client openssl curl
   ```

   Mais o **Docker**, que no WSL normalmente vem do Docker Desktop e não do
   `apt` — veja a seção abaixo. Em Linux nativo:
   `sudo apt-get install -y docker.io docker-compose-plugin`

   O `make up` confere tudo isso antes de qualquer coisa e diz exatamente o que
   estiver faltando.

### Se você está no Windows com WSL

Duas armadilhas, as duas fáceis de evitar:

**Clone o repositório dentro do Linux, não no disco do Windows.** Ou seja, em
`~/terraform-hermes-lab`, e **não** em `/mnt/c/Users/...`. No disco do Windows o
WSL ignora o `chmod`, a chave SSH fica com permissão aberta e o `ssh` se recusa
a usá-la. O `make up` detecta isso e para com uma mensagem explicando, mas é
mais simples já começar no lugar certo:

```bash
cd ~
git clone <url-deste-repo>
cd terraform-hermes-lab
```

**Use o Docker de dentro do WSL.** Se você usa Docker Desktop, ative a
integração com a sua distro em *Settings → Resources → WSL Integration*. Se
preferir instalar o Docker dentro do WSL, lembre de ligar o systemd — crie
`/etc/wsl.conf` com:

```ini
[boot]
systemd=true
```

e rode `wsl --shutdown` no PowerShell para reiniciar a distro. Sem isso o
serviço do Docker não sobe sozinho.

Confira que está tudo certo com:

```bash
docker run --rm hello-world
```

**Adiantando o download.** O `make up` baixa a imagem do Terraform e os
providers na primeira execução. Numa rede de evento, com muita gente baixando
ao mesmo tempo, isso vira gargalo. Se puder rodar antes, com calma:

```bash
make install
```

Ele só prepara o ambiente — não cria nada na sua conta e não custa nada.

---

## Subindo o laboratório

```bash
git clone <url-deste-repo>
cd terraform-hermes-lab
make up
```

É só isso. O `make up` vai, em ordem:

1. conferir os pré-requisitos;
2. pedir suas duas chaves da API e **validá-las na hora** contra a Locaweb
   Cloud (se estiverem erradas, você descobre em 5 segundos, não no meio do
   provisionamento);
3. gerar uma chave SSH exclusiva deste laboratório em `tools/`;
4. mostrar o que pretende fazer e pedir sua confirmação;
5. criar a VM;
6. acompanhar a instalação do Hermes, mostrando a fase atual;
7. imprimir IP, senha e o comando de acesso.

No passo 4 ele lista cada recurso que será criado, alterado ou destruído. Se
alguma coisa for ser **destruída** — a sua VM, por exemplo — ele avisa em
vermelho e exige que você digite `sim` por extenso. É a proteção contra rodar
`make up` distraído e perder a máquina que você já estava usando.

Para pular o resumo e a confirmação (útil quando você já sabe o que vai
acontecer):

```bash
make up-auto
```

**A instalação leva de 10 a 20 minutos.** O instalador oficial do Hermes monta
um ambiente Python + Node e baixa o Chromium — é normal demorar. Pode deixar
rodando e ir tomar um café.

Se a sua conexão cair no meio, nada se perde: rode `make status` para ver em
que fase está, ou `make logs` para acompanhar o log dentro da VM.

---

## Entrando na VM

```bash
make ssh
```

Ou, se preferir o comando cru, ele aparece em:

```bash
make credentials
```

Assim que entrar, o arquivo `/root/COMECE-AQUI.txt` resume os próximos passos.
O primeiro é:

```bash
hermes setup
```

Daí em diante, seguimos juntos no workshop.

---

## Ao terminar

```bash
make down
```

Destrói a VM, a rede e o IP público, e apaga a chave SSH local. **Rode isso ao
final do workshop** — a VM continua sendo cobrada enquanto existir.

---

## Comandos

| Comando | O que faz |
|---------|-----------|
| `make up` | Cria a VM e instala o Hermes (10–20 min), mostrando antes o que será feito |
| `make up-auto` | O mesmo, sem resumo nem confirmação |
| `make ssh` | Abre uma sessão SSH na VM |
| `make credentials` | Mostra IP, senha e comando de acesso |
| `make status` | Mostra em que fase está a instalação |
| `make logs` | Acompanha o log da instalação dentro da VM |
| `make down` | Destrói tudo |
| `make setup` | Refaz o `terraform.tfvars` (troca de conta, chave rotacionada) |
| `make install` | Baixa a imagem do Terraform e os providers, sem criar nada |
| `make help` | Lista todos os comandos |

---

## O que é criado na sua conta

| Recurso | Detalhe |
|---------|---------|
| VM | Ubuntu Server 24.04, plano `large` (8 GiB de RAM, disco de 160 GB) |
| Rede | Uma guest network isolada, `10.20.1.0/24` |
| IP público | Um, com port forward e firewall liberando **apenas a porta 22** |

Dentro da VM:

- **Hermes Agent** instalado no host pelo instalador oficial da Nous Research,
  em `/usr/local/bin/hermes`, com dados em `/root/.hermes`;
- **Docker Engine**, usado como *sandbox* das ações de terminal do agente —
  quando o Hermes executa um comando, ele roda dentro de um container com
  limites de CPU e memória, não direto no host;
- o **gateway rodando** como serviço de usuário do systemd (aparece em
  `systemctl --user`, não em `systemctl`). Ele sobe mesmo sem token do
  Telegram — apenas não há bot para servir até alguém configurar um. No
  workshop, quem quiser, acrescenta o token ao `/root/.hermes/.env` e roda
  `hermes gateway restart`.

Nenhuma porta HTTP é aberta e não há terminal web — o acesso é só por SSH.

---

## Se algo der errado

**`make up` falhou dizendo que as chaves foram rejeitadas.**
Gere novas no painel (Perfil → Gerar novas chaves API/Secretas) e rode
`make setup` de novo.

**A instalação passou de 20 minutos.**
Rode `make logs` e veja onde parou. O ponto mais comum de lentidão é o download
do Chromium. Se o log estiver parado há muito tempo, `make down && make up`
recomeça do zero.

**`make up` reclama que algum programa não está instalado.**
Ele imprime o comando de instalação de cada um. Instale e rode de novo.

**Perdi a senha.**
`make credentials` mostra de novo, enquanto o laboratório existir.

---

## Custo

A VM fica sendo cobrada enquanto existir. `make down` encerra a cobrança.
Não esqueça dele ao final do workshop.
