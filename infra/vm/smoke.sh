#!/usr/bin/env bash
# Smoke local da imagem de produção: builda as imagens, sobe o compose de
# produção (sem o tunnel) num diretório temporário e confere o básico.
# Uso: bash infra/vm/smoke.sh
# shellcheck disable=SC2015 # ok() sempre retorna 0 e fail() sai: A && B || C é seguro aqui.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
export REGISTRY=aurora-local TAG=local DATA_DIR="$TMP/data" COMPOSE_PROJECT_NAME=aurora-smoke
URL=http://127.0.0.1:8099
DOMAIN=aurora.henriquelopeslima.dev.br

dc() { docker compose --env-file "$TMP/app.env" -f "$TMP/compose.yaml" -f "$TMP/ports.yaml" "$@"; }
console() { dc exec -T php php bin/console "$@"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
ok() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; exit 1; }

cleanup() {
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  # Os dados pertencem aos uids dos containers; remove por dentro de um container.
  docker run --rm -v "$TMP:/t" alpine:3.20 rm -rf /t/data >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== build =="
docker build -q -f "$ROOT/docker/prod/Dockerfile" --target php -t "$REGISTRY/php:$TAG" "$ROOT"
docker build -q -f "$ROOT/docker/prod/Dockerfile" --target nginx -t "$REGISTRY/nginx:$TAG" "$ROOT"

echo "== up =="
cp "$ROOT/infra/vm/compose.yaml" "$ROOT/infra/vm/router.conf" "$TMP/"
docker network inspect edge >/dev/null 2>&1 || docker network create edge >/dev/null
cat > "$TMP/ports.yaml" <<'EOF'
services:
  nginx:
    ports: ["127.0.0.1:8099:80"]
EOF
cat > "$TMP/app.env" <<'EOF'
APP_SECRET=smoke-secret-0123456789abcdef
POSTGRES_PASSWORD=smokepostgres
MONGO_PASSWORD=smokemongo
MAILER_DSN=null://null
TUNNEL_TOKEN=unused
EOF
mkdir -p "$TMP/jwt"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TMP/jwt/private.pem" 2>/dev/null
openssl pkey -in "$TMP/jwt/private.pem" -pubout -out "$TMP/jwt/public.pem"
chmod 0644 "$TMP/jwt/"*.pem
mkdir -p "$DATA_DIR"/{postgres,mongo,uploads,storage}
docker run --rm -v "$DATA_DIR:/d" alpine:3.20 chown 33:33 /d/uploads /d/storage

dc up -d php nginx postgres mongo router

for _ in $(seq 60); do
  [ "$(code "$URL/login")" != 000 ] && console about >/dev/null 2>&1 && break
  sleep 2
done

# Mesma sequência do deploy.sh.
console doctrine:migrations:migrate -n --allow-no-migration
console doctrine:mongodb:schema:update
console app:mongo:migrations:execute

echo "== asserts =="
[ "$(code "$URL/")" = 200 ] && ok "home 200" || fail "home: $(code "$URL/")"
[ "$(code "$URL/cadastro")" = 200 ] && ok "/cadastro 200" || fail "/cadastro: $(code "$URL/cadastro")"
[ "$(code "$URL/login")" = 200 ] && ok "/login 200" || fail "/login: $(code "$URL/login")"

edge() { docker run --rm --network edge curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}' "$@"; }
[ "$(edge http://aurora-smoke-nginx-1/login)" = 200 ] && ok "nginx alcançável pela rede edge" || fail "rede edge"
[ "$(edge -H 'Host: pr-1-aurora.henriquelopeslima.dev.br' http://aurora-smoke-router-1/)" = 404 ] \
  && ok "router: PR sem preview dá 404" || fail "router PR sem preview"
[ "$(edge -H 'Host: evil.example' http://aurora-smoke-router-1/)" = 404 ] \
  && ok "router: host estranho dá 404" || fail "router host estranho"

asset=$(curl -s "$URL/" | grep -o '/assets/[^"]*\.css' | head -1)
[ -n "$asset" ] && [ "$(code "$URL$asset")" = 200 ] && ok "asset compilado $asset 200" || fail "asset compilado: '${asset}'"

redirect=$(curl -s -o /dev/null -w '%{redirect_url}' -H "Host: $DOMAIN" -H 'X-Forwarded-Proto: https' "$URL/painel")
case "$redirect" in
  "https://$DOMAIN/"*) ok "redirect atrás do proxy usa https e o domínio ($redirect)" ;;
  *) fail "redirect atrás do proxy: '$redirect'" ;;
esac

redirect=$(curl -s -o /dev/null -w '%{redirect_url}' -H "Host: $DOMAIN" -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: evil.example' "$URL/painel")
case "$redirect" in
  "https://$DOMAIN/"*) ok "X-Forwarded-Host do cliente é ignorado ($redirect)" ;;
  *) fail "X-Forwarded-Host do cliente mudou o host: '$redirect'" ;;
esac

plain=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: $DOMAIN" -H 'X-Forwarded-Proto: http' "$URL/login")
[ "$plain" = "301 https://$DOMAIN/login" ] && ok "acesso por http redireciona para https" || fail "acesso por http: '$plain'"

dc logs php 2>&1 | grep -q 'request\.' && ok "monolog escreve no stderr" || fail "nenhum log do monolog no stderr do php"

docker run --rm -v "$DATA_DIR/uploads:/u" alpine:3.20 sh -c 'echo ok > /u/smoke.txt'
[ "$(code "$URL/uploads/smoke.txt")" = 200 ] && ok "upload servido em /uploads" || fail "upload: $(code "$URL/uploads/smoke.txt")"
dc up -d --force-recreate php nginx >/dev/null 2>&1
for _ in $(seq 30); do [ "$(code "$URL/login")" = 200 ] && break; sleep 2; done
[ "$(code "$URL/uploads/smoke.txt")" = 200 ] && ok "upload sobrevive a recriar containers" || fail "upload após recriar: $(code "$URL/uploads/smoke.txt")"

echo "SMOKE OK"
