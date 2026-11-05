# Infra do aurora (GCP + OpenTofu)

Ambiente constante em **https://aurora.henriquelopeslima.dev.br**, criado só com código.

```
push na main ─▶ GitHub Actions ─(WIF)─▶ Artifact Registry ─▶ VM (docker compose)
usuário ─HTTPS─▶ Cloudflare ─Tunnel─▶ cloudflared ─▶ nginx ─▶ php ─▶ postgres / mongo
```

| Peça | Onde |
|---|---|
| VM `aurora` (e2-medium, São Paulo), sem nenhuma porta aberta além de SSH via IAP | `vm.tf`, `network.tf` |
| Disco `aurora-data` (bancos + uploads), snapshot diário com 7 dias, protegido contra destroy | `vm.tf` |
| Imagens `php` e `nginx` de produção | `../docker/prod/`, `registry.tf` |
| Compose de produção, boot e deploy da VM | `vm/compose.yaml`, `vm/startup.sh`, `vm/deploy.sh` |
| Segredos (gerados aqui) no Secret Manager | `secrets.tf` |
| Tunnel, DNS da app e do Resend | `cloudflare.tf` |
| Deploy pelo GitHub Actions sem chave (Workload Identity Federation) | `github.tf`, `../.github/workflows/deploy.yml` |
| Uptime check com alerta por e-mail | `monitoring.tf` |

Custo estimado: ~US$ 35–40/mês (VM e2-medium em São Paulo + 40 GB de disco + snapshots). O resto fica no free tier.

## Pré-requisitos

- `tofu` (`mise use -g opentofu`), `gcloud` e `gh`.
- `gcloud auth login` e `gcloud auth application-default login` com a conta dona do projeto `aurora-513810`.
- Um API token da Cloudflare com **Account › Cloudflare Tunnel › Edit** e **Zone › DNS › Edit** (zona `henriquelopeslima.dev.br`): `export CLOUDFLARE_API_TOKEN=...`
- No Resend: adicionar o domínio `aurora.henriquelopeslima.dev.br` e criar uma API key.

## Bootstrap (uma vez)

O state precisa existir antes do resto:

```bash
gcloud storage buckets create gs://aurora-513810-tfstate \
  --project aurora-513810 --location southamerica-east1 --uniform-bucket-level-access
gcloud storage buckets update gs://aurora-513810-tfstate --versioning
```

Depois, em `infra/`, copie `terraform.tfvars.example` para `terraform.tfvars` e preencha: IDs de conta e zona da Cloudflare, a API key do Resend e o valor DKIM que o Resend mostra para `resend._domainkey`.

## Subida

```bash
cd infra
tofu init
tofu apply

# Valores não secretos que o workflow usa:
gh variable set GCP_WIF_PROVIDER --body "$(tofu output -raw GCP_WIF_PROVIDER)"
gh variable set GCP_DEPLOY_SA    --body "$(tofu output -raw GCP_DEPLOY_SA)"

# Primeiro deploy (ou qualquer push na main):
gh workflow run deploy.yml && gh run watch
```

Com os registros DNS no ar, clique em **Verify** no domínio do Resend.

## Primeiro admin

O banco começa vazio. Cadastre-se em `/cadastro`, confirme pelo e-mail e então:

```bash
gcloud compute ssh aurora --zone southamerica-east1-a --tunnel-through-iap
sudo docker exec aurora-postgres-1 psql -U aurora -d aurora \
  -c "UPDATE app_user SET roles = '[\"ROLE_ADMIN\"]' WHERE email = 'seu-email@exemplo.com';"
```

## Operação

- **Logs:** Cloud Logging (driver `gcplogs`), ou na VM: `sudo docker compose -p aurora logs -f php`.
- **Deploy manual de uma versão:** na VM, `sudo aurora-deploy <sha>`. A VM também volta sozinha na última versão boa depois de reboot ou recriação (`/mnt/data/image_tag`).
- **Mudou `vm/compose.yaml` ou `vm/deploy.sh`:** `tofu apply` atualiza a metadata; vale no próximo deploy, sem reboot.
- **Recriar a VM:** `tofu apply -replace=google_compute_instance.aurora`. Os dados ficam no disco `aurora-data`.

## Restaurar um snapshot

```bash
gcloud compute snapshots list --filter="sourceDisk~aurora-data"
gcloud compute instances stop aurora --zone southamerica-east1-a
gcloud compute instances detach-disk aurora --disk aurora-data --zone southamerica-east1-a
gcloud compute disks create aurora-data-restore --source-snapshot <snapshot> --zone southamerica-east1-a
gcloud compute instances attach-disk aurora --disk aurora-data-restore --device-name aurora-data --zone southamerica-east1-a
gcloud compute instances start aurora --zone southamerica-east1-a
```

Depois, alinhe o código: troque o disco em `vm.tf` (ou `tofu import` do disco restaurado) para o próximo `apply` não reverter.

## Destruir

`tofu destroy` derruba tudo **menos** o disco de dados (`prevent_destroy`). Para apagar os dados também, remova o `prevent_destroy` em `vm.tf` de propósito e rode de novo. O bucket de state é manual.
