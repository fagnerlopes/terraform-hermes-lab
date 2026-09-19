# Laboratório Hermes — TDC São Paulo

Sobe uma VM na **Locaweb Cloud** com o **Hermes Agent** já instalado, pronta
para o workshop. Você roda um comando, espera, e entra na máquina por SSH.

A configuração do agente (provedor de LLM, GitHub, Telegram) **não** é feita
aqui: fazemos isso juntos, ao vivo, no workshop.

---

## Antes de começar

Você precisa de:

1. **Sua conta no Locaweb Cloud, ativada com o cupom do TDC.**

   Contrate em <https://www.locaweb.com.br/locaweb-cloud/> e aplique o cupom
   que o time do TDC enviou para você. Ele foi gerado para este workshop e é
   suficiente para rodar o experimento durante as duas primeiras faturas:
   seguindo o roteiro do workshop, você não terá nenhum pagamento nesse
   período.

   E o melhor: o agente que você vai construir hoje não morre quando a palestra
   acabar. Ele continua rodando, na sua conta, na sua infraestrutura, para você
   continuar mexendo, quebrando e refazendo com calma.

   O Locaweb Cloud é pós-pago: você paga pelo que usar, e o cupom é abatido
   desse consumo. O roteiro usa **uma** VM — é para ela que o cupom foi
   dimensionado. Veja [Custo](#custo) antes de subir mais alguma coisa, e
   [Ao terminar](#ao-terminar) para desligar quando quiser.

   Não recebeu o cupom? Procure o time do TDC antes de seguir.

2. **As chaves de API da sua conta.** Como gerar:
   - acesse <https://painel-cloud.locaweb.com.br>
   - clique no seu nome (canto superior direito) → **Perfil**
   - clique em **Gerar novas chaves API/Secretas**
   - deixe a aba aberta — você vai colar as duas chaves daqui a pouco

3. **Linux, WSL (Windows) ou macOS** com estes programas instalados:

   ```bash
   sudo apt-get update
   sudo apt-get install -y make jq openssh-client openssl curl
   ```

   Mais o **Docker**, que no WSL normalmente vem do Docker Desktop e não do
   `apt` — veja a seção abaixo. Em Linux nativo:
   `sudo apt-get install -y docker.io docker-compose-plugin`

   O `make up` confere tudo isso antes de qualquer coisa e diz exatamente o que
   estiver faltando.

4. **Uma chave de API de um provedor de LLM** e **um token do GitHub**. Não
   entram no Terraform e não são pedidos pelo `make up`: você os informa dentro
   da VM, no `hermes setup`, que é o primeiro passo do workshop. Deixe os dois
   à mão antes de começar — é o único pré-requisito que o laboratório não
   consegue verificar para você, e sem ele o agente não funciona.

   O token do GitHub é um *Personal Access Token (classic)*, gerado em
   <https://github.com/settings/tokens>, com os escopos:

   - `repo` — criar e editar repositórios, push, pull, branches
   - `write:packages` — publicar imagens no ghcr.io
   - `workflow` — opcional, só se você for disparar workflows pela API

   Gere antes de vir e guarde: o GitHub mostra o token uma única vez.

5. **(Opcional) Um bot do Telegram**, se quiser conversar com o agente pelo
   celular. A ligação é feita ao vivo, mas o bot você cria antes:

   1. Fale com o [@BotFather](https://t.me/BotFather) e envie `/newbot`
   2. Escolha um nome e um username terminado em `bot`
   3. Guarde o token que ele devolve
   4. Fale com o [@userinfobot](https://t.me/userinfobot) para descobrir o seu
      **id numérico** — é ele que autoriza o acesso ao bot, não o @username

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
integração com a sua distro em *Settings → Resources → WSL Integration*, e
marque *Settings → General → Start Docker Desktop when you sign in*. Se
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

> **Reaproveitou um IP?** Se você já tinha destruído um laboratório antes, a
> Locaweb pode devolver o mesmo IP para a VM nova, e o seu `~/.ssh/known_hosts`
> ainda guarda a chave da máquina antiga — o `ssh` recusa com
> `REMOTE HOST IDENTIFICATION HAS CHANGED`. O `make ssh` não sofre disso. Se
> usar o `ssh` na mão e bater nesse erro:
> `ssh-keygen -f ~/.ssh/known_hosts -R <IP>`

**A instalação leva de 15 a 25 minutos.** O instalador oficial do Hermes monta
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

Esse comando também grava um **`CREDENCIAIS.txt`** na pasta do repositório, com
IP, usuário e senha. Ele não vai para o Git. **Guarde esse arquivo antes de ir
embora** — depois que o laboratório for destruído, a senha não é recuperável.

O acesso por SSH é **somente com chave**. A senha não funciona por SSH: a VM
fica com a porta 22 aberta para a internet, e senha ali é convite para força
bruta. Ela serve no **console web** do painel da Locaweb, que é o seu resgate
caso perca a chave em `tools/`.

Assim que entrar, o arquivo `/root/COMECE-AQUI.txt` resume os próximos passos.
O primeiro é:

```bash
hermes setup
```

É aqui que entram a **chave de LLM** e a **conta do GitHub** do item 4 dos
pré-requisitos. Daí em diante, seguimos juntos no workshop.

> Ao terminar, o `hermes setup` sugere na tela o comando `hermes gateway`. Se
> você rodar, aparece um erro em vermelho: *a gateway is already running under
> systemd (user)*. **Não é problema.** O gateway já sobe junto com a VM, e a
> CLI está apenas impedindo que um segundo suba por cima. Para ver o estado,
> `hermes gateway status`.

---

## Cofounder

A VM já vem com as dependências do Cofounder instaladas, então o instalador
roda em segundos. Chame-o **de dentro da pasta do projeto** — em `$HOME` ele não
configura projeto nenhum:

```bash
mkdir -p ~/meu-app && cd ~/meu-app
/bin/bash -c "$(curl -fsSL https://cofounder.locaweb.com.br/install.sh)"
```

---

## Ao terminar

**Não desligue nada quando a palestra acabar.** Deixe o agente de pé, volte
nele durante a semana, quebre, refaça, instale o que quiser dentro da VM. Foi
para isso que o cupom existe — ele cobre esse laboratório nas duas primeiras
faturas.

O que fazer antes de ir embora depende de onde você está rodando.

### Se o computador não é seu

É o caso da máquina emprestada do evento. Apague suas credenciais dela:

```bash
make clear
```

Remove desta pasta o `terraform.tfvars` (suas chaves de API), o
`terraform.tfstate` (que guarda a senha da VM), o `CREDENCIAIS.txt` e a sua
chave SSH em `tools/`. Ele mostra o que vai apagar e pede confirmação.

**Leve o `CREDENCIAIS.txt` com você antes** — tire uma foto, copie para o
celular, mande para você mesmo. Com a senha dele você ainda entra na VM pelo
console web do painel, mesmo sem a chave SSH.

E atenção: junto com o state vai embora o `make down`. Se quiser destruir a VM
depois, será pelo painel da Locaweb.

### Voltando à VM em casa

Se você rodou o `make clear` na máquina do evento, tudo o que sobrou é o
`CREDENCIAIS.txt`. Ele basta: a VM continua no ar e a senha continua valendo no
console web.

**1. Entrar agora, sem instalar nada.** Abra
<https://painel-cloud.locaweb.com.br>, localize a VM, abra o **console** e entre
como `root` com a senha do `CREDENCIAIS.txt`. Você já está dentro — o agente e
tudo o que você configurou continuam lá.

**2. Voltar a entrar por SSH** (o console web é desconfortável para trabalhar).
No seu computador de casa, gere um par de chaves:

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/hermes_lab
cat ~/.ssh/hermes_lab.pub
```

Copie a linha inteira que o `cat` mostrou. No console web da VM, cole-a assim —
substituindo `COLE_AQUI` pela linha:

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo 'COLE_AQUI' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

A partir daí, do seu terminal, usando o IP do `CREDENCIAIS.txt`:

```bash
ssh -i ~/.ssh/hermes_lab -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null root@SEU_IP
```

**3. O que não funciona mais.** Os comandos `make ssh`, `make status`,
`make logs` e `make down` leem o IP do `terraform.tfstate`, que ficou na máquina
do evento. Em casa, use o `ssh` acima. E para destruir a VM quando terminar, vá
pelo painel da Locaweb — sem o state, o Terraform não sabe o que destruir.

### Se o computador é seu

Deixe tudo como está e continue usando. Quando terminar de experimentar:

```bash
make down
```

Destrói a VM, a rede e o IP público, e apaga a chave SSH local junto com o
`CREDENCIAIS.txt`.

Você também pode destruir e subir de novo quantas vezes quiser: `make down`
hoje, `make up` amanhã. São uns 15 minutos para ter tudo no ar de novo, do
zero. O que não volta é o que você tiver configurado dentro da VM.

Esgotado o cupom, o que continuar de pé entra na sua fatura. Se quiser seguir
com o agente no ar além disso, ótimo — só vale saber que a partir dali a conta
é sua.

### Se as suas chaves rodaram numa máquina que não é sua

O `make clear` apaga os arquivos, mas não há como garantir que ninguém copiou
nada antes. O mais seguro é gerar chaves novas no painel (Perfil → **Gerar
novas chaves API/Secretas**): isso invalida as antigas, tenham elas ficado onde
tiverem ficado.


---

## Comandos

| Comando | O que faz |
|---------|-----------|
| `make up` | Cria a VM e instala o Hermes (10–20 min), mostrando antes o que será feito |
| `make up-auto` | O mesmo, sem resumo nem confirmação |
| `make ssh` | Abre uma sessão SSH na VM |
| `make credentials` | Mostra IP e senha, e grava o `CREDENCIAIS.txt` |
| `make status` | Mostra em que fase está a instalação |
| `make logs` | Acompanha o log da instalação dentro da VM |
| `make down` | Destrói tudo, e apaga a chave local e o `CREDENCIAIS.txt` |
| `make clear` | Apaga só as suas credenciais desta máquina, sem tocar na VM |
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

O Locaweb Cloud é pós-pago: a VM gera consumo enquanto existir, e o cupom do
TDC é abatido dele. O cupom é suficiente para rodar o experimento durante as
duas primeiras faturas — seguindo o roteiro do workshop, você não terá nenhum
pagamento nesse período.

O roteiro é **uma** VM. Subir várias ao mesmo tempo consome o cupom mais rápido
do que ele cobre, e a diferença entra na sua fatura.

Quando for passar um tempo sem mexer, `make down` encerra o consumo: ele destrói
a VM, a rede e o IP público. Voltar custa 15 minutos de `make up`.

---

## Preparando uma máquina para vários participantes

Esta seção é para quem **organiza** o workshop, não para quem participa.

Se você vai clonar o disco de uma máquina para distribuir aos participantes,
lembre que **um clone de disco não respeita o `.gitignore`**: tudo que estiver
na pasta vai junto. Depois de testar o laboratório nessa máquina, ela contém
suas chaves de API, o state do seu lab e a sua chave SSH — e cada participante
receberia uma cópia de tudo isso, compartilhando as mesmas credenciais.

Antes de gerar a imagem, nesta ordem:

```bash
cd ~/terraform-hermes-lab

# 1. Destrua o laboratório de teste ENQUANTO o state ainda existe
make down

# 2. Remova tudo que é seu e que o clone levaria junto
rm -rf terraform.tfvars terraform.tfstate* tools/ CREDENCIAIS.txt .terraform/

# 3. Confirme que não sobrou nada
git status --short        # tem que sair vazio

# 4. Deixe o download pesado pronto na imagem
git pull                  # garanta que a imagem sai com o código mais recente
make install              # baixa a imagem do Terraform e os providers
```

O passo 4 é o que mais se paga: sem ele, dezenas de pessoas baixam os mesmos
providers ao mesmo tempo na rede do evento, e isso vira gargalo logo no começo
da aula.

Vale também deixar instalados os pré-requisitos da seção
[Antes de começar](#antes-de-começar), para que ninguém gaste tempo com
`apt-get` durante o workshop.

---

## Licença

[FSL-1.1-ALv2](LICENSE) — Functional Source License, que converte para
Apache 2.0 dois anos após cada publicação. É a mesma licença do
[CloudWeaver](https://github.com/fagnerlopes/cloud-weaver).
