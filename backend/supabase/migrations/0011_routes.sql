-- ============================================================
-- Sellable routes (e.g. bar crawls). Buying a route unlocks every
-- place it contains. Stops' exact data stays gated like any place.
-- ============================================================
create table public.routes (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  summary text,
  description text,
  city_id uuid references public.cities(id) on delete set null,
  kind text not null default 'bar_crawl',
  cover_url text,
  is_free boolean not null default false,
  price_cents int not null default 299,
  currency text not null default 'USD',
  product_id text,
  distance_m int,
  duration_min int,
  featured boolean not null default false,
  status text not null default 'draft' check (status in ('draft','published','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.route_stops (
  route_id uuid not null references public.routes(id) on delete cascade,
  position int not null,
  place_id uuid not null references public.places(id) on delete cascade,
  note text,
  primary key (route_id, position)
);
create index idx_route_stops_place on public.route_stops(place_id);

alter table public.user_entitlements add column if not exists route_id uuid references public.routes(id) on delete cascade;
create unique index if not exists uq_entitlement_route on public.user_entitlements(user_id, route_id) where route_id is not null;

alter table public.routes enable row level security;
alter table public.route_stops enable row level security;
create policy routes_read on public.routes for select using (status = 'published');
grant select on public.routes to anon, authenticated;
-- (no direct select policy/grant on route_stops — access only via get_route_details)

-- defined before routes_public, which calls it
create or replace function public.route_stop_count(p_route_id uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.route_stops where route_id = p_route_id;
$$;

create view public.routes_public with (security_invoker = true) as
select r.id, r.slug, r.title, r.summary, r.city_id, r.kind, r.cover_url,
  r.is_free, r.price_cents, r.currency, r.product_id, r.distance_m, r.duration_min,
  r.featured, r.created_at,
  public.route_stop_count(r.id) as stop_count
from public.routes r where r.status = 'published';
grant select on public.routes_public to anon, authenticated;

-- A place is unlocked if free/promo, directly entitled, OR the user owns a route containing it.
create or replace function public.is_place_unlocked(p_place_id uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select
    coalesce((
      select (pl.access_type in ('free','promotionalFree'))
        or (pl.promotion_start_at is not null and pl.promotion_end_at is not null
            and now() between pl.promotion_start_at and pl.promotion_end_at)
      from public.places pl where pl.id = p_place_id and pl.status = 'published'
    ), false)
    or (p_user is not null and exists (
      select 1 from public.user_entitlements e
      where e.user_id = p_user and e.place_id = p_place_id and e.revoked_at is null))
    or (p_user is not null and exists (
      select 1 from public.user_entitlements e
      join public.route_stops rs on rs.route_id = e.route_id
      where e.user_id = p_user and e.route_id is not null and e.revoked_at is null
        and rs.place_id = p_place_id));
$$;

create or replace function public.route_owned(p_route_id uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_free from public.routes where id = p_route_id and status='published'), false)
    or (p_user is not null and exists (
      select 1 from public.user_entitlements e
      where e.user_id = p_user and e.route_id = p_route_id and e.revoked_at is null));
$$;

-- Full route with ordered stops. Stops reveal exact data only when the route
-- is owned (or the stop place is itself free/unlocked).
create or replace function public.get_route_details(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r public.routes%rowtype; v_uid uuid := auth.uid(); v_owned boolean; v_stops jsonb;
begin
  select * into r from public.routes where slug = p_slug and status='published';
  if not found then return jsonb_build_object('error','not_found'); end if;
  v_owned := public.route_owned(r.id, v_uid);
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', s.position, 'note', s.note,
      'id', p.id, 'slug', p.slug, 'teaser_title', p.teaser_title, 'teaser_description', p.teaser_description,
      'approx_lat', p.approx_lat, 'approx_lng', p.approx_lng, 'primary_category_id', p.primary_category_id,
      'locked', not (v_owned or public.is_place_unlocked(p.id, v_uid)),
      'full_title', case when (v_owned or public.is_place_unlocked(p.id, v_uid)) then p.full_title else null end,
      'exact_lat', case when (v_owned or public.is_place_unlocked(p.id, v_uid)) then p.exact_lat else null end,
      'exact_lng', case when (v_owned or public.is_place_unlocked(p.id, v_uid)) then p.exact_lng else null end,
      'business_name', case when (v_owned or public.is_place_unlocked(p.id, v_uid)) then p.business_name else null end
    ) order by s.position), '[]'::jsonb)
    into v_stops
  from public.route_stops s join public.places p on p.id = s.place_id where s.route_id = r.id;
  return jsonb_build_object(
    'id', r.id, 'slug', r.slug, 'title', r.title, 'summary', r.summary, 'description', r.description,
    'kind', r.kind, 'city_id', r.city_id, 'cover_url', r.cover_url, 'is_free', r.is_free,
    'price_cents', r.price_cents, 'currency', r.currency, 'product_id', r.product_id,
    'distance_m', r.distance_m, 'duration_min', r.duration_min, 'featured', r.featured,
    'owned', v_owned, 'stops', v_stops);
end $$;

grant execute on function public.get_route_details(text) to anon, authenticated;
grant execute on function public.route_stop_count(uuid) to anon, authenticated;
revoke execute on function public.is_place_unlocked(uuid, uuid) from public;
revoke execute on function public.route_owned(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.route_stop_count(uuid) from public;
