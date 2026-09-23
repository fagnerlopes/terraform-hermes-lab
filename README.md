# Hermes Agent na Locaweb Cloud

Sobe uma VM na **Locaweb Cloud** com o **Hermes Agent** instalado e conectado
ao **Telegram**.

## Pré-requisitos

- Conta no [Locaweb Cloud](https://www.locaweb.com.br/locaweb-cloud/).
- Chaves de API da conta: em <https://painel-cloud.locaweb.com.br>, clique no
  seu nome → **Perfil** → **Gerar novas chaves API/Secretas**.
- Linux, macOS ou WSL com Docker e:

  ```bash
  sudo apt-get install -y make jq openssh-client openssl curl
  ```

  No WSL, clone o repositório dentro do Linux (`~/`), não em `/mnt/c/`.
- Chave de API de um provedor de LLM.
- Token do GitHub (*Personal Access Token classic*, em
  <https://github.com/settings/tokens>) com os escopos `repo` e
  `write:packages`.
- Bot do Telegram:
  1. No [@BotFather](https://t.me/BotFather), envie `/newbot` e guarde o token.
  2. No [@userinfobot](https://t.me/userinfobot), anote o seu id numérico.

## 1. Subir a VM

```bash
git clone <url-deste-repo>
cd terraform-hermes-lab
make up
```

O `make up` pede as chaves de API da Locaweb, mostra o plano, pede
confirmação e cria a VM. A instalação leva de 15 a 25 minutos; no fim ele
imprime IP e senha e grava o `CREDENCIAIS.txt`.

## 2. Configurar o Hermes

```bash
make ssh
hermes setup
```

Informe a chave do provedor de LLM e o token do GitHub.

## 3. Conectar ao Telegram

Ainda na VM, substitua o token e o id:

```bash
printf 'TELEGRAM_BOT_TOKEN=SEU_TOKEN\nTELEGRAM_ALLOWED_USERS=SEU_ID\n' >> /root/.hermes/.env
chmod 600 /root/.hermes/.env
hermes gateway restart
```

Mande uma mensagem para o seu bot no Telegram.

## 4. Destruir

```bash
make down
```

Remove a VM, a rede, o IP público, a chave SSH local e o `CREDENCIAIS.txt`.

## Comandos

| Comando | O que faz |
|---------|-----------|
| `make up` | Cria a VM e instala o Hermes |
| `make up-auto` | O mesmo, sem confirmação |
| `make ssh` | Abre uma sessão SSH na VM |
| `make credentials` | Mostra IP e senha e grava o `CREDENCIAIS.txt` |
| `make status` | Mostra a fase da instalação |
| `make logs` | Acompanha o log da instalação na VM |
| `make down` | Destrói tudo |
| `make clear` | Apaga as credenciais locais, sem tocar na VM |
| `make setup` | Refaz o `terraform.tfvars` |
| `make help` | Lista todos os comandos |

## Licença

[FSL-1.1-ALv2](LICENSE)
