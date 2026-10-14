# Self-hosted backend on OVH

The backend runs as the official self-hosted Supabase Docker stack on the shared
`7am-vps-clients` OVH server (51.195.148.252), isolated from the client sites there.

| | |
|---|---|
| Public API | `https://api.secretplaces.7am.digital` (CloudPanel reverse-proxy site, Let's Encrypt) |
| Legacy API | `https://api.secretplaces.7am.agency` — same backend; keep it: app 1.0.0 (and every install of it) has this URL baked in |
| Website | `https://secretplaces.7am.digital` (CloudPanel static site; legacy `secretplaces.7am.agency` still serves the same files) |
| Stack dir | `/opt/secretplaces-supabase` (secrets in `.env`, mode 600 — never commit) |
| Gateway | Envoy on `127.0.0.1:61000` — the only thing nginx proxies to |
| Postgres pooler | `127.0.0.1:61432` (session) / `127.0.0.1:61543` (transaction) |
| Studio | `127.0.0.1:61300` only — `ssh -L 61300:127.0.0.1:61300 ubuntu@51.195.148.252`, then http://localhost:61300 |

## Isolation

- Every published port is bound to `127.0.0.1` (`docker-compose.override.yml`); nothing listens publicly.
- Envoy's catch-all Studio route and `/pg/` (postgres-meta) return 403/404 publicly (`envoy-block-studio.patch`).
- Auth: Sign in with Apple only (`GOTRUE_EXTERNAL_APPLE_CLIENT_ID=com.secretplaces.app`); email/phone/anonymous signup off.
- Client sites, MariaDB and CloudPanel's nginx config are untouched.

## Files here

- `docker-compose.override.yml` — copy of the server's override (no secrets; values come from `.env`).
- `envoy-block-studio.patch` — applied to `volumes/api/envoy/lds.template.yaml` (original kept as `.orig`).
  Re-apply after `update.sh` pulls a new stack version.
- `migrate_from_cloud.py` — one-off: replayed `backend/supabase/migrations` onto the new DB, rewriting the
  cloud project's hard-coded UUIDs to the local ones by slug (seed migrations use random UUIDs).

## Function secrets (in `.env`, passed via the override)

`APPLE_ROOT_CERTS` (AppleRootCA-G3, SHA-256 `63:34:3A:BF:…:91:79`), `APPLE_APP_ID=6822694406`,
`APPLE_BUNDLE_ID`, `SYNC_SECRET`. Not set yet: `GOOGLE_PLACES_KEY` (only needed to re-run `enrich-photos`).

## Common operations

```bash
ssh ubuntu@51.195.148.252
cd /opt/secretplaces-supabase
sudo docker compose ps                    # health
sudo docker compose logs -f functions     # edge function logs
# deploy edge functions: copy backend/supabase/functions/<name> into volumes/functions/<name>, then
sudo docker compose restart functions
# run a migration
sudo docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 -1 < 00xx_name.sql
```

Events refresh every 6 h via `pg_cron` → `http://api-gw:8000/functions/v1/sync-events` (secrets in Vault:
`sync_events_secret`, `events_sync_anon`).

Backups: not configured yet — add a nightly `pg_dump` off-box before launch.
