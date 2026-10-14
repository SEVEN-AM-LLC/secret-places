-- ============================================================
-- City pass: one purchase unlocks every paid place in a city.
-- New cities are sold this way instead of one App Store product per place
-- (hundreds of IAPs to create/review, and a hard cap of 10k per app).
-- A paid place with no product_id of its own is unlocked by its city's pass;
-- places that keep their own product (Kyiv) still sell individually, and a
-- pass for their city unlocks them too.
-- ============================================================
alter table public.cities add column if not exists pass_product_id text unique
  check (pass_product_id is null or pass_product_id ~ '^[A-Za-z0-9_.]+$');
alter table public.cities add column if not exists pass_price_cents int not null default 499;

alter table public.user_entitlements add column if not exists city_id uuid references public.cities(id) on delete cascade;
create unique index if not exists uq_entitlement_city on public.user_entitlements(user_id, city_id) where city_id is not null;

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
        and rs.place_id = p_place_id))
    or (p_user is not null and exists (
      select 1 from public.user_entitlements e
      join public.places pl on pl.city_id = e.city_id
      where e.user_id = p_user and e.city_id is not null and e.revoked_at is null
        and pl.id = p_place_id));
$$;

create or replace function public.get_place_details(p_place_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  p public.places%rowtype; c public.cities%rowtype; v_uid uuid := auth.uid(); v_unlocked boolean;
  v_teaser jsonb; v_images jsonb; v_tags jsonb;
begin
  select * into p from public.places where id = p_place_id and status = 'published';
  if not found then return jsonb_build_object('error','not_found'); end if;
  select * into c from public.cities where id = p.city_id;
  v_unlocked := public.is_place_unlocked(p_place_id, v_uid);
  select coalesce(jsonb_agg(jsonb_build_object('url', pi.url, 'sort', pi.sort, 'is_hero', pi.is_hero) order by pi.sort), '[]'::jsonb)
    into v_images from public.place_images pi
    where pi.place_id = p_place_id and (v_unlocked or pi.preview_allowed);
  select coalesce(jsonb_agg(t.tag), '[]'::jsonb) into v_tags from public.place_tags t where t.place_id = p_place_id;
  v_teaser := jsonb_build_object(
    'id', p.id, 'slug', p.slug, 'locked', not v_unlocked,
    'teaser_title', p.teaser_title, 'teaser_description', p.teaser_description, 'hero_image_url', case when v_unlocked then p.hero_image_url end,
    'approx_lat', p.approx_lat, 'approx_lng', p.approx_lng,
    'country_id', p.country_id, 'region_id', p.region_id, 'city_id', p.city_id,
    'neighborhood_id', p.neighborhood_id, 'primary_category_id', p.primary_category_id,
    'access_type', p.access_type, 'price_cents', p.price_cents, 'currency', p.currency,
    -- A paid place without its own product is sold through its city's pass.
    'product_id', coalesce(p.product_id, c.pass_product_id),
    'unlock_scope', case when p.product_id is null and c.pass_product_id is not null then 'city' else 'place' end,
    'city_title', c.title,
    'travel_time_min', p.travel_time_min, 'recommended_transport', p.recommended_transport,
    'best_time', p.best_time, 'best_season', p.best_season, 'expected_duration_min', p.expected_duration_min,
    'crowd_level', p.crowd_level, 'price_level', p.price_level,
    'accessibility_info', p.accessibility_info, 'safety_info', p.safety_info,
    'mobile_signal', p.mobile_signal, 'what_to_bring', p.what_to_bring,
    'rating', p.rating, 'ratings_count', p.ratings_count,
    'has_entry_password', (p.entry_password is not null),
    'featured', p.featured, 'editors_choice', p.editors_choice, 'images', v_images, 'tags', v_tags,
    'is_free_now', (p.access_type in ('free','promotionalFree')
      or (p.promotion_start_at is not null and p.promotion_end_at is not null
          and now() between p.promotion_start_at and p.promotion_end_at)));
  if not v_unlocked then return v_teaser; end if;   -- SENSITIVE FIELDS NEVER INCLUDED
  return v_teaser || jsonb_build_object(
    'full_title', p.full_title, 'full_description', p.full_description,
    'exact_lat', p.exact_lat, 'exact_lng', p.exact_lng, 'exact_address', p.exact_address, 'business_name', p.business_name,
    'walking_instructions', p.walking_instructions, 'parking_info', p.parking_info,
    'insider_tips', p.insider_tips, 'photo_spot', p.photo_spot, 'website', p.website, 'booking_url', p.booking_url,
    'entry_password', p.entry_password, 'entry_note', p.entry_note,
    'apple_maps_url', p.apple_maps_url, 'google_maps_url', p.google_maps_url, 'opening_hours', p.opening_hours);
end $$;
grant execute on function public.get_place_details(uuid) to anon, authenticated;
