#!/usr/bin/env bash
# Teste local do aurora-preview: sobe previews de verdade atrás do router, sem GCP nem Cloudflare.
# Uso: bash infra/vm/preview-test.sh
# shellcheck disable=SC2015 # ok() sempre retorna 0 e fail() sai: A && B || C é seguro aqui.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
# PREVIEW_PRUNE=0: o docker image prune -af do preview apagaria as imagens desta máquina.
export REGISTRY=aurora-local TAG=local PREVIEW_CF=0 PREVIEW_MAX=2 PREVIEW_PRUNE=0 \
  PREVIEW_ROOT="$TMP/previews" PREVIEW_LOCK="$TMP/lock" PREVIEW_COMPOSE="$ROOT/infra/vm/compose.preview.yaml"
ROUTER=preview-test-router

preview() { bash "$ROOT/infra/vm/preview.sh" "$@"; }
# Código de saída sem abortar o set -e; stdout/stderr ficam em $TMP/out e $TMP/err.
rc() { local r=0; preview "$@" >"$TMP/out" 2>"$TMP/err" || r=$?; echo "$r"; }
H() { echo "pr-$1-aurora.henriquelopeslima.dev.br"; }
get() { docker run --rm --network edge curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}' -H "Host: $1" "http://$ROUTER$2"; }
ok() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; tail -n 20 "$TMP/err" "$TMP/out" 2>/dev/null; exit 1; }

cleanup() {
  for d in "$TMP"/previews/pr-*; do
    [ -d "$d" ] && docker compose -p "aurora-pr-${d##*/pr-}" down -v --remove-orphans >/dev/null 2>&1 || true
  done
  docker rm -f "$ROUTER" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== build =="
docker build -q -f "$ROOT/docker/prod/Dockerfile" --target preview -t "$REGISTRY/php-preview:$TAG" "$ROOT"
docker build -q -f "$ROOT/docker/prod/Dockerfile" --target nginx -t "$REGISTRY/nginx:$TAG" "$ROOT"
docker network inspect edge >/dev/null 2>&1 || docker network create edge >/dev/null
docker rm -f "$ROUTER" >/dev/null 2>&1 || true
docker run -d --name "$ROUTER" --network edge \
  -v "$ROOT/infra/vm/router.conf:/etc/nginx/conf.d/default.conf:ro" nginx:1.27-alpine >/dev/null

echo "== asserts =="
for args in "up abc local" "up 0 local" "up 1;reboot local" "up 1 x;y" "down abc"; do
  # shellcheck disable=SC2086 # o split por espaço é o objetivo: cada caso vira argv.
  [ "$(rc $args)" = 2 ] || fail "argumento inválido '$args' não deu exit 2"
done
[ ! -e "$PREVIEW_ROOT" ] && ok "argumento inválido: exit 2 sem efeito" || fail "argumento inválido criou estado"

[ "$(rc up 101 local)" = 0 ] || fail "up 101"
[ "$(tail -1 "$TMP/out")" = "url=https://$(H 101)" ] && ok "up 101: última linha é a url" || fail "url: '$(tail -1 "$TMP/out")'"

[ "$(get "$(H 101)" /login)" = 200 ] && ok "login via router" || fail "login via router: $(get "$(H 101)" /login)"

users=$(docker exec aurora-pr-101-postgres-1 psql -U aurora -d aurora -tAc 'SELECT count(*) FROM app_user')
[ "$users" -gt 0 ] && ok "fixtures carregadas ($users usuários)" || fail "fixtures: $users usuários"

docker exec -u www-data aurora-pr-101-php-1 sh -c 'echo ok > /var/www/assets/uploads/t'
[ "$(get "$(H 101)" /uploads/t)" = 200 ] && ok "upload servido pelo nginx do preview" || fail "upload: $(get "$(H 101)" /uploads/t)"

edge_members=$(docker network inspect edge -f '{{range .Containers}}{{.Name}} {{end}}' | tr ' ' '\n' | grep '^aurora-pr-101-' || true)
[ "$edge_members" = aurora-pr-101-nginx-1 ] && ok "só o nginx do preview entra na edge" || fail "edge: '$edge_members'"
[ "$(get aurora-pr-101-php-1.henriquelopeslima.dev.br /)" = 404 ] && ok "host com nome de container dá 404" || fail "host container"
[ "$(get pr-101a-aurora.henriquelopeslima.dev.br /)" = 404 ] && ok "host fora do padrão dá 404" || fail "host fora do padrão"

[ "$(docker inspect -f '{{.HostConfig.Memory}}' aurora-pr-101-mongo-1)" = 402653184 ] \
  && ok "mongo com limite de 384m" || fail "limite do mongo"

[ "$(rc up 101 local)" = 0 ] || fail "re-up 101"
[ "$(get "$(H 101)" /uploads/t)" = 404 ] && ok "re-up reseta os volumes" || fail "re-up: upload sobreviveu"

r1=0 r2=0
PREVIEW_MAX=3 preview up 102 local >"$TMP/102.log" 2>&1 & p1=$!
PREVIEW_MAX=3 preview up 103 local >"$TMP/103.log" 2>&1 & p2=$!
wait "$p1" || r1=$?
wait "$p2" || r2=$?
[ "$r1$r2" = 00 ] && ok "up paralelo serializado pelo lock" || { tail -5 "$TMP/102.log" "$TMP/103.log"; fail "up paralelo: $r1 $r2"; }
[ "$(rc down 103)" = 0 ] || fail "down 103"

[ "$(rc up 104 local)" = 3 ] && grep -q 'limite de previews' "$TMP/err" \
  && ok "limite de previews: exit 3" || fail "limite: $(cat "$TMP/err")"

touch -d '8 days ago' "$PREVIEW_ROOT/pr-102/last_up"
[ "$(rc up 104 local)" = 0 ] || fail "up 104 após gc"
[ ! -e "$PREVIEW_ROOT/pr-102" ] && [ -z "$(docker ps -aq -f name=aurora-pr-102-)" ] \
  && ok "gc destrói preview com mais de 7 dias" || fail "gc: pr-102 ainda existe"

mkdir -p "$PREVIEW_ROOT/pr-105" && touch "$PREVIEW_ROOT/pr-105/last_up"
[ "$(rc down 105)" = 0 ] && [ ! -e "$PREVIEW_ROOT/pr-105" ] && ok "down de preview pela metade" || fail "down parcial"

[ "$(rc down 104)" = 0 ] || fail "down 104"
[ -z "$(docker ps -aq -f name=aurora-pr-104-)" ] && [ "$(get "$(H 104)" /login)" = 404 ] \
  && ok "down remove containers e o host volta a 404" || fail "down 104"

# Job cancelado: o ssh sem tty não manda sinal, e o up só morre ao escrever na sessão fechada.
# stdout/stderr fechados simulam a sessão morta de forma determinística (a escrita falha na hora).
preview up 106 local >&- 2>&- || true
[ ! -e "$PREVIEW_ROOT/pr-106" ] && ok "up com a sessão fechada sai antes de criar estado" || fail "up órfão criou pr-106"

[ "$(rc down 999)" = 0 ] && ok "down inexistente: exit 0" || fail "down 999"

echo "PREVIEW TEST OK"
