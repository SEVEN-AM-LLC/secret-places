-- get_enrich_key(name): returns an enrichment provider API key from Vault for
-- the enrich-photos edge function. SECURITY DEFINER + service-role-only,
-- mirroring check_sync_secret. Allowlisted key names only. The key values live
-- ONLY in Vault (set out-of-band via vault.create_secret), never in a migration
-- or in git.
create or replace function public.get_enrich_key(p_name text)
returns text
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
declare
  v text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'forbidden';
  end if;
  if p_name not in ('foursquare_api_key', 'google_places_key') then
    raise exception 'unknown key %', p_name;
  end if;
  select decrypted_secret into v
  from vault.decrypted_secrets
  where name = p_name
  limit 1;
  return v;
end;
$$;

revoke all on function public.get_enrich_key(text) from public, anon, authenticated;
grant execute on function public.get_enrich_key(text) to service_role;
