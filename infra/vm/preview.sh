#!/usr/bin/env bash
# Previews por PR na VM: `sudo aurora-preview up <pr> <tag> | down <pr> | gc` (CI via SSH/IAP).
# Cada preview é o projeto compose aurora-pr-<n>, servido em https://pr-<n>-aurora.henriquelopeslima.dev.br.
# Saída: 0 ok; 2 argumento inválido; 3 limite de previews atingido.
# Overrides (teste local, infra/vm/preview-test.sh): REGISTRY, PREVIEW_COMPOSE (caminho), PREVIEW_MAX,
# PREVIEW_ROOT, PREVIEW_LOCK, PREVIEW_CF=0 (sem Cloudflare), PREVIEW_PRUNE=0 (sem image prune).
# shellcheck disable=SC2015 # A && B || usage: qualquer falha da validação cai no usage, que sai.
set -euo pipefail

ROOT_DIR=${PREVIEW_ROOT:-/opt/aurora/previews}
LOCK=${PREVIEW_LOCK:-/var/lock/aurora-deploy}
DOMAIN=henriquelopeslima.dev.br
MAX_AGE_MIN=$((7 * 24 * 60))

usage() { echo "uso: aurora-preview up <pr> <tag> | down <pr> | gc" >&2; exit 2; }
valid_pr() { [[ "$1" =~ ^[1-9][0-9]{0,6}$ ]]; }
valid_tag() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }
md() { curl -fsS -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }

cmd=${1:-}
case "$cmd" in
  up) [ $# = 3 ] && valid_pr "$2" && valid_tag "$3" || usage ;;
  down) [ $# = 2 ] && valid_pr "$2" || usage ;;
  gc) [ $# = 1 ] || usage ;;
  *) usage ;;
esac

# Mesmo lock do deploy de prod: serializa os dois, e o prune do prod não apaga uma imagem recém-puxada.
exec 9>"$LOCK"
flock 9

# Cloudflare: o token fica no Secret Manager e os ids na metadata (infra/preview.tf).
cf_init() {
  [ -n "${CF_TOKEN:-}" ] && return 0
  CF_TOKEN=$(gcloud secrets versions access latest --secret=aurora-preview-cf-token)
  CF_ACC=$(md aurora-cf-account)
  CF_ZONE=$(md aurora-cf-zone)
}

# O token vai por process substitution, fora da linha de comando (ps). Erro: corpo da resposta no stderr.
cf() {
  local method=$1 path=$2 out
  shift 2
  out=$(curl -sS --fail-with-body -X "$method" -H @<(printf 'Authorization: Bearer %s\n' "$CF_TOKEN") \
    -H 'Content-Type: application/json' "https://api.cloudflare.com/client/v4$path" "$@") \
    || { echo "cloudflare $method $path: $out" >&2; return 1; }
  printf '%s' "$out"
}

app_ids() { cf GET "/accounts/$CF_ACC/access/apps" | jq -r --arg h "$1" '.result[] | select(.domain == $h) | .id'; }
dns_ids() { cf GET "/zones/$CF_ZONE/dns_records?type=CNAME&name=$1" | jq -r '.result[].id'; }

# Idempotente: o app do Access entra antes do CNAME, então o host nunca fica público sem login.
cf_up() {
  [ "${PREVIEW_CF:-1}" = 0 ] && return 0
  local pr=$1 host="pr-$1-aurora.$DOMAIN" ids body policy tunnel
  cf_init

  ids=$(app_ids "$host")
  if [ -z "$ids" ]; then
    policy=$(md aurora-preview-policy)
    body=$(jq -n --arg h "$host" --arg n "aurora preview pr-$pr" --arg p "$policy" \
      '{name: $n, type: "self_hosted", domain: $h, destinations: [{type: "public", uri: $h}],
        policies: [{id: $p, precedence: 1}], session_duration: "24h"}')
    cf POST "/accounts/$CF_ACC/access/apps" --data "$body" >/dev/null
  fi

  ids=$(dns_ids "$host")
  if [ -z "$ids" ]; then
    tunnel=$(md aurora-tunnel-cname)
    body=$(jq -n --arg h "$host" --arg t "$tunnel" --arg c "aurora preview (PR #$pr)" \
      '{type: "CNAME", name: $h, content: $t, proxied: true, ttl: 1, comment: $c}')
    cf POST "/zones/$CF_ZONE/dns_records" --data "$body" >/dev/null
  fi

  # Um app novo leva ~1 min para valer na borda: os containers só sobem depois do redirect do Access.
  # --resolve pelo IP do host de prod (mesma borda): evita o cache negativo do DNS do host recém-criado.
  local edge i
  edge=$(getent ahostsv4 "aurora.$DOMAIN" | awk 'NR == 1 {print $1}')
  for i in $(seq 36); do
    case "$(curl -s -o /dev/null -w '%{redirect_url}' --resolve "$host:443:$edge" "https://$host/")" in
      https://*.cloudflareaccess.com/*) return 0 ;;
    esac
    sleep 5
  done
  echo "o Access não protegeu $host em 180s; o preview não subiu" >&2
  return 1
}

# Ordem inversa do cf_up: o CNAME sai antes do app do Access. Recurso inexistente não é erro.
cf_down() {
  [ "${PREVIEW_CF:-1}" = 0 ] && return 0
  local host="pr-$1-aurora.$DOMAIN" ids id
  cf_init

  ids=$(dns_ids "$host")
  for id in $ids; do cf DELETE "/zones/$CF_ZONE/dns_records/$id" >/dev/null; done
  ids=$(app_ids "$host")
  for id in $ids; do cf DELETE "/accounts/$CF_ACC/access/apps/$id" >/dev/null; done
}

prune() {
  [ "${PREVIEW_PRUNE:-1}" = 0 ] && return 0
  docker image prune -af >/dev/null || echo "aviso: docker image prune falhou" >&2
}

# Só pelo nome do projeto: funciona sem compose.yaml nem app.env (preview pela metade) e sem projeto.
reset() { docker compose -p "aurora-pr-$1" down -v --remove-orphans >/dev/null; }

teardown() {
  local pr=$1
  cf_down "$pr"
  reset "$pr"
  rm -rf "${ROOT_DIR:?}/pr-$pr"
}

gc() {
  # shortcut: gc só roda no início de cada up ou à mão; um preview esquecido segura RAM até lá. Upgrade: timer systemd se isso acontecer.
  local f pr
  [ -d "$ROOT_DIR" ] || return 0
  while IFS= read -r f; do
    pr=${f%/last_up}
    pr=${pr##*/pr-}
    valid_pr "$pr" || continue
    echo "gc: pr-$pr sem up há mais de 7 dias" >&2
    teardown "$pr"
  done < <(find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -path "$ROOT_DIR/pr-*/last_up" -mmin +"$MAX_AGE_MIN")
}

up() {
  local pr=$1 tag=$2 dir="$ROOT_DIR/pr-$1" max count
  gc

  max=${PREVIEW_MAX:-$(md aurora-preview-max)}
  mkdir -p "$ROOT_DIR"
  count=$(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -name 'pr-*' | wc -l)
  if [ ! -d "$dir" ] && [ "$count" -ge "$max" ]; then
    echo "limite de previews ($max) atingido; feche um PR ou rode aurora-preview down <pr>" >&2
    exit 3
  fi

  mkdir -p "$dir"
  touch "$dir/last_up"
  cf_up "$pr"

  if [ -n "${PREVIEW_COMPOSE:-}" ]; then
    cp "$PREVIEW_COMPOSE" "$dir/compose.yaml"
  else
    md aurora-preview-compose > "$dir/compose.yaml"
  fi
  # Reset a cada push: banco, uploads e segredos novos.
  reset "$pr"

  (umask 077 && cat > "$dir/app.env" <<EOF
APP_SECRET=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
MONGO_PASSWORD=$(openssl rand -hex 16)
EOF
  )
  rm -rf "$dir/jwt" && mkdir -p "$dir/jwt"
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$dir/jwt/private.pem" 2>/dev/null
  openssl pkey -in "$dir/jwt/private.pem" -pubout -out "$dir/jwt/public.pem"
  chmod 0755 "$dir/jwt"
  chmod 0644 "$dir/jwt/"*.pem   # segredo descartável; www-data da imagem precisa ler

  if [ -z "${REGISTRY:-}" ]; then
    REGISTRY=$(md aurora-registry)
    gcloud auth configure-docker "${REGISTRY%%/*}" --quiet >/dev/null 2>&1
  fi
  export REGISTRY TAG="$tag" PR="$pr" APP_HOST="pr-$pr-aurora.$DOMAIN"
  dc() { docker compose -p "aurora-pr-$pr" --env-file "$dir/app.env" -f "$dir/compose.yaml" "$@"; }
  console() { dc exec -T php php bin/console "$@"; }

  dc up -d --quiet-pull

  local i
  for i in $(seq 60); do
    console about >/dev/null 2>&1 && break
    [ "$i" = 60 ] && { echo "php do preview não respondeu em 120s" >&2; exit 1; }
    sleep 2
  done

  # Mesma sequência do deploy.sh; depois as fixtures, que só existem em APP_ENV=dev.
  console doctrine:migrations:migrate -n --allow-no-migration
  console doctrine:mongodb:schema:update
  console app:mongo:migrations:execute
  dc exec -T -e APP_ENV=dev php php bin/console doctrine:fixtures:load -n \
    --purge-exclusions=city --purge-exclusions=state

  # Imagens de pushes anteriores do PR encheriam o disco de boot.
  prune
  echo "url=https://$APP_HOST"
}

down() {
  local pr=$1
  [ -d "$ROOT_DIR/pr-$pr" ] || return 0
  teardown "$pr"
  prune
}

case "$cmd" in
  up) up "$2" "$3" ;;
  down) down "$2" ;;
  gc) gc; prune ;;
esac
