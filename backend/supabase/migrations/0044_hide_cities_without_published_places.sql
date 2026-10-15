-- Draft waves add cities before their places are published (their passes wait for App Review).
-- Clients query public.cities directly (search, city lists), so a city is visible only once it has
-- at least one published place. Server-side code (verify-purchase, definer RPCs) is unaffected.
create or replace function public.city_has_published_places(p_city_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.places where city_id = p_city_id and status = 'published');
$$;
revoke execute on function public.city_has_published_places(uuid) from public;
grant execute on function public.city_has_published_places(uuid) to anon, authenticated;

drop policy if exists read_cities on public.cities;
create policy read_cities on public.cities for select using (public.city_has_published_places(id));
