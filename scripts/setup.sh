#!/usr/bin/env bash
# Interactive first-run setup: checks prerequisites, collects the Locaweb Cloud
# API credentials, validates them against the real API and writes
# terraform.tfvars. Called automatically by `make up` when tfvars is missing.
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
API_URL="https://painel-cloud.locaweb.com.br/client/api"
TFVARS="terraform.tfvars"

say()  { printf "%b\n" "$1"; }
ok()   { printf "%b\n" "${GREEN}✓${NC} $1"; }
warn() { printf "%b\n" "${YELLOW}⚠${NC}  $1"; }
err()  { printf "%b\n" "${RED}✗${NC} $1" >&2; }

say "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
say "${BLUE}  Laboratório Hermes — configuração inicial${NC}"
say "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
say ""

# ---------------------------------------------------------------- prereqs ---
say "${BLUE}1/5 Verificando pré-requisitos${NC}"
missing=0
need() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1"
    else
        err "$1 não encontrado — instale com: ${2}"
        missing=1
    fi
}
# Most of this workshop's audience runs Windows + WSL with Docker Desktop, where
# "install it with apt" is the wrong advice — the Docker that matters lives on
# the Windows side.
is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }

if is_wsl; then
    docker_hint="Docker Desktop no Windows, com a integração WSL ligada (Settings -> Resources -> WSL Integration)"
else
    docker_hint="sudo apt-get install -y docker.io"
fi

need docker      "$docker_hint"
need make        "sudo apt-get install -y make"
need jq          "sudo apt-get install -y jq"
need ssh-keygen  "sudo apt-get install -y openssh-client"
need openssl     "sudo apt-get install -y openssl"
need curl        "sudo apt-get install -y curl"

# The daemon comes BEFORE the compose plugin on purpose. `command -v docker`
# above only proves the name resolves in PATH — it never runs anything — and
# `docker compose version` is a client-side call that never reaches the daemon
# either. So a stopped Docker Desktop passes every check above and only blows up
# later, inside `docker compose build`. Checking it here turns the most common
# Windows failure into the message that actually fixes it.
if command -v docker >/dev/null 2>&1; then
    if ! docker info >/dev/null 2>&1; then
        err "o Docker está instalado, mas não respondeu."
        if is_wsl; then
            say "    Abra o Docker Desktop e espere o ícone ficar verde."
            say "    Para não passar por isso de novo, marque em Settings -> General:"
            say "    'Start Docker Desktop when you sign in'."
        else
            say "    Inicie o serviço com: sudo systemctl start docker"
        fi
        missing=1
    else
        ok "docker rodando"
        # Only meaningful once the daemon answers; otherwise it would report a
        # missing plugin when the real problem is an app that is simply closed.
        if ! docker compose version >/dev/null 2>&1; then
            if is_wsl; then
                err "'docker compose' não disponível — atualize o Docker Desktop, que já traz o compose"
            else
                err "'docker compose' não disponível — instale com: sudo apt-get install -y docker-compose-plugin"
            fi
            missing=1
        else
            ok "docker compose"
        fi
    fi
fi

if [ "$missing" -ne 0 ]; then
    say ""
    err "Instale o que falta acima e rode de novo."
    exit 1
fi
say ""

# ------------------------------------------------------------------- name ---
# Names the network, the keypair and the instance (main.tf). CloudStack requires
# it to be unique within the account, so anyone running a second lab in the same
# account has to change it here.
say "${BLUE}2/5 Nome do laboratório${NC}"
say "Esse nome identifica a VM, a rede e a chave no painel da Locaweb."
say "Precisa ser único na sua conta. Enter aceita o padrão."
say ""

VM_NAME_DEFAULT="hermes-lab"
# Same rule as the vm_name validation in variables.tf. Checking it here turns a
# Terraform error at plan time into an immediate re-prompt.
VM_NAME_RE='^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$'

while :; do
    printf "%b" "Nome do laboratório [${VM_NAME_DEFAULT}]: "
    read -r VM_NAME || { say ""; err "Entrada interrompida."; exit 1; }
    VM_NAME="${VM_NAME:-$VM_NAME_DEFAULT}"
    if [[ "$VM_NAME" =~ $VM_NAME_RE ]]; then
        break
    fi
    err "De 3 a 32 caracteres: minúsculas, números e hífen, começando e terminando com letra ou número."
done
ok "Nome: ${VM_NAME}"
say ""

# ------------------------------------------------------------ existing file -
if [ -f "$TFVARS" ]; then
    warn "$TFVARS já existe."
    read -r -p "Sobrescrever? (digite 'sim' para confirmar): " overwrite
    if [ "$overwrite" != "sim" ]; then
        say "Mantendo o arquivo atual. Nada foi alterado."
        exit 0
    fi
    say ""
fi

# --------------------------------------------------------------- questions --
say "${BLUE}3/5 Credenciais do Locaweb Cloud${NC}"
say ""
say "  Para gerar suas chaves:"
say "    1. Acesse ${BLUE}https://painel-cloud.locaweb.com.br${NC}"
say "    2. Clique no seu nome (canto superior direito) > Perfil"
say "    3. Clique em 'Gerar novas chaves API/Secretas'"
say "    4. Copie a Chave da API e a Chave secreta"
say ""

read -r -p "  Chave da API: " API_KEY
# Secret is read without echo so it never lands on screen or in shell history.
read -r -s -p "  Chave secreta: " SECRET_KEY
say ""
say ""

if [ -z "$API_KEY" ] || [ -z "$SECRET_KEY" ]; then
    err "As duas chaves são obrigatórias."
    exit 1
fi

# Fail early on the most common paste accident rather than at apply time.
case "$API_KEY$SECRET_KEY" in
    *[[:space:]]*) err "As chaves não podem conter espaços. Copie novamente do painel."; exit 1 ;;
esac

# ------------------------------------------------------------- validation ---
say "${BLUE}4/5 Validando as chaves na API${NC}"

urlencode() {
    local s="$1" i c out=""
    # Byte-wise, like every reference implementation: in a UTF-8 locale bash
    # would slice by character and encode multi-byte input differently.
    local LC_ALL=C
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '%s' "$out"
}

# CloudStack signs the request over the lowercased, alphabetically sorted,
# url-encoded parameter string; the request itself keeps the original casing.
validate_credentials() {
    local key_enc sig_base sig sig_enc url body
    key_enc="$(urlencode "$API_KEY")"
    sig_base="apikey=${key_enc}&command=listzones&response=json"
    sig="$(printf '%s' "$sig_base" | tr '[:upper:]' '[:lower:]' \
           | openssl dgst -sha1 -hmac "$SECRET_KEY" -binary | openssl base64)"
    sig_enc="$(urlencode "$sig")"
    url="${API_URL}?apiKey=${key_enc}&command=listZones&response=json&signature=${sig_enc}"

    body="$(curl -sS --max-time 20 "$url" 2>/dev/null)" || return 2   # 2 = could not reach
    case "$body" in
        *listzonesresponse*zone*) return 0 ;;   # authenticated, zones returned
        *401*|*"unable to verify user credentials"*|*"Unable to find account"*) return 1 ;;
        *) return 2 ;;
    esac
}

set +e
validate_credentials
result=$?
set -e

case "$result" in
    0) ok "Chaves válidas — a API respondeu com suas zonas." ;;
    1) err "A API rejeitou essas chaves."
       say ""
       say "  Gere novas chaves no painel (Perfil > 'Gerar novas chaves API/Secretas')"
       say "  e rode ${BLUE}make setup${NC} de novo."
       exit 1 ;;
    # Never block on an inconclusive check: a proxy, a DNS hiccup or an odd
    # character in the key must not stop someone whose credentials are fine.
    *) warn "Não consegui validar agora (rede, proxy ou API fora do ar)."
       warn "Seguindo mesmo assim — se as chaves estiverem erradas, o 'make up' vai falhar." ;;
esac
say ""

# ----------------------------------------------------------------- write ----
say "${BLUE}5/5 Gravando $TFVARS${NC}"
umask 077
cat > "$TFVARS" <<EOF
# Gerado por scripts/setup.sh. Contém segredos — não versione este arquivo.
cloudstack_api_key    = "${API_KEY}"
cloudstack_secret_key = "${SECRET_KEY}"
vm_name               = "${VM_NAME}"
EOF
chmod 600 "$TFVARS"
ok "$TFVARS criado (permissão 600)."
say ""
say "${GREEN}Pronto. Rode:${NC} ${BLUE}make up${NC}"
