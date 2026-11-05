#!/usr/bin/env bash
# Startup script da VM (metadata startup-script). Roda a cada boot e é idempotente.
set -euo pipefail

DEVICE=/dev/disk/by-id/google-aurora-data
DATA=/mnt/data

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
# aurora-preview fala com a API da Cloudflare via jq.
command -v jq >/dev/null || { apt-get update -qq && apt-get install -y -qq jq; }

# Logs dos containers no Cloud Logging.
want='{"log-driver":"gcplogs"}'
if [ "$(cat /etc/docker/daemon.json 2>/dev/null)" != "$want" ]; then
  echo "$want" > /etc/docker/daemon.json
  systemctl restart docker
fi

for _ in $(seq 30); do [ -e "$DEVICE" ] && break; sleep 1; done

# Nunca formata um disco que já tem filesystem: é nele que moram os dados.
# Só blkid rc=2 (nenhuma assinatura) formata; qualquer outro erro (ex.: 8, ambíguo) para tudo.
rc=0
blkid -p "$DEVICE" >/dev/null 2>&1 || rc=$?
if [ "$rc" = 2 ]; then
  mkfs.ext4 -m 0 -F "$DEVICE"
elif [ "$rc" != 0 ]; then
  echo "blkid rc=$rc em $DEVICE: não formato nem monto; investigue o disco" >&2
  exit 1
fi

mkdir -p "$DATA"
uuid=$(blkid -s UUID -o value "$DEVICE")
grep -q "UUID=$uuid" /etc/fstab || echo "UUID=$uuid $DATA ext4 defaults,nofail 0 2" >> /etc/fstab
mountpoint -q "$DATA" || mount "$DATA"

mkdir -p "$DATA"/{postgres,mongo,uploads,storage}
chown 70:70 "$DATA/postgres"                  # postgres:16-alpine
chown 999:999 "$DATA/mongo"                   # mongo:7.0
chown 33:33 "$DATA/uploads" "$DATA/storage"   # www-data da imagem php

# deploy.sh e preview.sh vêm sempre frescos da metadata, para um `tofu apply` valer sem reboot.
for name in aurora-deploy aurora-preview; do
  cat > "/usr/local/bin/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
f=\$(mktemp)
curl -fsS -H 'Metadata-Flavor: Google' \\
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/$name > "\$f"
exec bash "\$f" "\$@"
EOF
  chmod 0755 "/usr/local/bin/$name"
done

# VM recriada ou reiniciada volta sozinha na última versão deployada com sucesso.
if [ -s "$DATA/image_tag" ]; then
  /usr/local/bin/aurora-deploy "$(cat "$DATA/image_tag")"
fi
