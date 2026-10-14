-- ============================================================
-- Hide venue photos of LOCKED paid places.
-- hero_image_url holds a real photo of the venue (Google Places). For a paid
-- place, that photo + the public approximate area is enough to find it with a
-- reverse image search — i.e. it leaks exactly what the purchase unlocks.
-- From now on the photo is returned only when the place is free / promo-free
-- or the caller owns it (is_place_unlocked), on every public path:
--   • places_public view   • direct column access on places (revoked)
--   • get_place_details     • nearby_places
-- ============================================================

create or replace function public.place_public_photo(p_place_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when public.is_place_unlocked(p.id, auth.uid()) then p.hero_image_url end
  from public.places p where p.id = p_place_id and p.status = 'published';
$$;
revoke execute on function public.place_public_photo(uuid) from public;
grant execute on function public.place_public_photo(uuid) to anon, authenticated;

-- The raw column is no longer readable by clients; they get it via the view/RPCs.
revoke select (hero_image_url) on public.places from anon, authenticated;

create or replace view public.places_public with (security_invoker = true) as
select p.id, p.slug, p.teaser_title, p.teaser_description, public.place_public_photo(p.id) as hero_image_url, p.approx_lat, p.approx_lng,
  p.country_id, p.region_id, p.city_id, p.neighborhood_id, p.primary_category_id,
  p.access_type, p.price_cents, p.currency, p.product_id, p.promotion_start_at, p.promotion_end_at,
  (p.access_type in ('free','promotionalFree')
    or (p.promotion_start_at is not null and p.promotion_end_at is not null
        and now() between p.promotion_start_at and p.promotion_end_at)) as is_free_now,
  p.travel_time_min, p.recommended_transport, p.best_time, p.best_season, p.expected_duration_min,
  p.crowd_level, p.price_level, p.accessibility_info, p.safety_info, p.mobile_signal, p.what_to_bring,
  p.rating, p.ratings_count, p.featured, p.editors_choice, p.created_at, p.updated_at
from public.places p where p.status = 'published';
grant select on public.places_public to anon, authenticated;

create or replace function public.get_place_details(p_place_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  p public.places%rowtype; v_uid uuid := auth.uid(); v_unlocked boolean;
  v_teaser jsonb; v_images jsonb; v_tags jsonb;
begin
  select * into p from public.places where id = p_place_id and status = 'published';
  if not found then return jsonb_build_object('error','not_found'); end if;
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
    'access_type', p.access_type, 'price_cents', p.price_cents, 'currency', p.currency, 'product_id', p.product_id,
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

create or replace function public.nearby_places(p_lat double precision, p_lng double precision, p_radius_m double precision, p_limit int default 50)
returns table (id uuid, slug text, teaser_title text, teaser_description text, hero_image_url text,
  approx_lat double precision, approx_lng double precision, primary_category_id uuid,
  access_type text, price_cents int, currency text, is_free_now boolean,
  rating numeric, ratings_count int, distance_m double precision, unlocked boolean)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.slug, p.teaser_title, p.teaser_description,
    case when public.is_place_unlocked(p.id, auth.uid()) then p.hero_image_url end,
    p.approx_lat, p.approx_lng, p.primary_category_id, p.access_type, p.price_cents, p.currency,
    (p.access_type in ('free','promotionalFree')
      or (p.promotion_start_at is not null and p.promotion_end_at is not null
          and now() between p.promotion_start_at and p.promotion_end_at)) as is_free_now,
    p.rating, p.ratings_count,
    round(extensions.ST_Distance(p.geog, extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat),4326)::extensions.geography) / 100.0) * 100 as distance_m,
    public.is_place_unlocked(p.id, auth.uid()) as unlocked
  from public.places p
  where p.status = 'published' and p.geog is not null
    and extensions.ST_DWithin(p.geog, extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat),4326)::extensions.geography, p_radius_m)
  order by p.geog operator(extensions.<->) extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat),4326)::extensions.geography
  limit p_limit;
$$;
grant execute on function public.nearby_places(double precision, double precision, double precision, int) to anon, authenticated;
