#!/usr/bin/env bash
# Deploy de uma versão na VM: `sudo aurora-deploy <tag>` (CI via SSH/IAP, e startup.sh no boot).
# Qualquer falha sai != 0, e a tag só vira "a versão de boot" no fim.
set -euo pipefail

TAG=${1:?uso: aurora-deploy <tag>}
APP=/opt/aurora
DATA=/mnt/data

exec 9>/var/lock/aurora-deploy
flock 9

md() { curl -fsS -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
secret() { gcloud secrets versions access latest --secret="$1"; }

mkdir -p "$APP/jwt"
umask 077

REGISTRY=$(md aurora-registry)
md aurora-compose > "$APP/compose.yaml"

# Atribuições soltas: com set -e, uma falha aqui aborta (dentro de echo não abortaria).
app_secret=$(secret aurora-app-secret)
postgres_password=$(secret aurora-postgres-password)
mongo_password=$(secret aurora-mongo-password)
mailer_dsn=$(secret aurora-mailer-dsn)
tunnel_token=$(secret aurora-tunnel-token)
cat > "$APP/app.env" <<EOF
APP_SECRET=$app_secret
POSTGRES_PASSWORD=$postgres_password
MONGO_PASSWORD=$mongo_password
MAILER_DSN=$mailer_dsn
TUNNEL_TOKEN=$tunnel_token
EOF

# Arquivo novo + mv: o php em execução monta ./jwt, e um fetch falho não pode esvaziar a chave.
secret aurora-jwt-private-key > "$APP/jwt/private.pem.new"
secret aurora-jwt-public-key > "$APP/jwt/public.pem.new"
chgrp -R 33 "$APP/jwt"   # www-data da imagem php lê as chaves
chmod 0750 "$APP/jwt"
chmod 0640 "$APP/jwt/"*.new
mv -f "$APP/jwt/private.pem.new" "$APP/jwt/private.pem"
mv -f "$APP/jwt/public.pem.new" "$APP/jwt/public.pem"

gcloud auth configure-docker "${REGISTRY%%/*}" --quiet >/dev/null 2>&1

export REGISTRY TAG DATA_DIR="$DATA"
dc() { docker compose -p aurora --env-file "$APP/app.env" -f "$APP/compose.yaml" "$@"; }
console() { dc exec -T php php bin/console "$@"; }

dc pull --quiet
dc up -d --remove-orphans

for i in $(seq 60); do
  console about >/dev/null 2>&1 && break
  [ "$i" = 60 ] && { echo "php não respondeu em 120s" >&2; exit 1; }
  sleep 2
done

# Mesma sequência do infra/vm/smoke.sh.
console doctrine:migrations:migrate -n --allow-no-migration
console doctrine:mongodb:schema:update
console app:mongo:migrations:execute

echo "$TAG" > "$DATA/image_tag"

# Versões antigas encheriam o disco de boot; rollback puxa de novo do registry.
# Falhar aqui não desfaz um deploy que já deu certo.
docker image prune -af >/dev/null || echo "aviso: docker image prune falhou" >&2

echo "deploy ok: $TAG"
