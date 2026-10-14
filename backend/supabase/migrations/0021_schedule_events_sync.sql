-- Schedule the real events feed refresh (sync-events Edge Function).
-- pg_cron calls the function every 6 hours via pg_net, authenticating with
-- a Vault-stored secret so no key is ever hardcoded here.
--
-- ONE-TIME per environment (run manually, NOT in this migration — values
-- are secret): create the two Vault secrets the job reads:
--   select vault.create_secret('<random>', 'sync_events_secret', 'gate for sync-events');
--   select vault.create_secret('<anon key>', 'events_sync_anon', 'anon JWT for gateway auth');
-- The Edge Function accepts x-sync-secret == this Vault secret via
-- public.check_sync_secret (below), the service-role key, or SYNC_SECRET env.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Oracle-safe secret check: only service_role may call it (the edge fn does).
create or replace function public.check_sync_secret(p text)
returns boolean language sql stable security definer set search_path = vault, public as $$
  select exists (select 1 from vault.decrypted_secrets where name='sync_events_secret' and decrypted_secret = p);
$$;
revoke execute on function public.check_sync_secret(text) from public, anon, authenticated;
grant execute on function public.check_sync_secret(text) to service_role;

-- (Re)create the 6-hourly job.
do $$
begin
  perform cron.unschedule('sync-events-6h') where exists (select 1 from cron.job where jobname='sync-events-6h');
end $$;

select cron.schedule('sync-events-6h', '15 */6 * * *', $job$
  select net.http_post(
    url := 'http://api-gw:8000/functions/v1/sync-events'  -- self-hosted: gateway on the docker network,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='events_sync_anon'),
      'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets where name='sync_events_secret')
    ),
    body := jsonb_build_object('pages', 3),
    timeout_milliseconds := 25000
  );
$job$);
