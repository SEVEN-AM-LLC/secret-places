-- ============================================================
-- Wikimedia Commons photos + awards (Wikidata, CC0).
-- photo_url/photo_credit are separate from hero_image_url on purpose: Commons
-- photos MUST be shown with author + licence, and app 1.0.0 renders
-- hero_image_url without a credit line. Only 1.0.1+ reads these fields.
-- Same rule as 0028: a locked paid place never exposes its photo (a photo +
-- the public area is enough to find it with a reverse image search).
-- Awards (e.g. 'michelin_star') are public — they sell the unlock.
-- ============================================================

alter table public.places
  add column if not exists wikidata text,
  add column if not exists photo_url text,
  add column if not exists photo_credit text,
  add column if not exists awards text[] not null default '{}';
create index if not exists places_wikidata_idx on public.places (wikidata);

revoke select (photo_url, photo_credit) on public.places from anon, authenticated;
-- places has column-level grants (0028): the view is security_invoker, so awards needs its own grant.
grant select (awards) on public.places to anon, authenticated;

create or replace function public.place_public_commons(p_place_id uuid)
returns table (url text, credit text) language sql stable security definer set search_path = public as $$
  select p.photo_url, p.photo_credit from public.places p
  where p.id = p_place_id and p.status = 'published' and p.photo_url is not null
    and public.is_place_unlocked(p.id, auth.uid());
$$;
revoke execute on function public.place_public_commons(uuid) from public;
grant execute on function public.place_public_commons(uuid) to anon, authenticated;

create or replace view public.places_public with (security_invoker = true) as
select p.id, p.slug, p.teaser_title, p.teaser_description, public.place_public_photo(p.id) as hero_image_url, p.approx_lat, p.approx_lng,
  p.country_id, p.region_id, p.city_id, p.neighborhood_id, p.primary_category_id,
  p.access_type, p.price_cents, p.currency, p.product_id, p.promotion_start_at, p.promotion_end_at,
  (p.access_type in ('free','promotionalFree')
    or (p.promotion_start_at is not null and p.promotion_end_at is not null
        and now() between p.promotion_start_at and p.promotion_end_at)) as is_free_now,
  p.travel_time_min, p.recommended_transport, p.best_time, p.best_season, p.expected_duration_min,
  p.crowd_level, p.price_level, p.accessibility_info, p.safety_info, p.mobile_signal, p.what_to_bring,
  p.rating, p.ratings_count, p.featured, p.editors_choice, p.created_at, p.updated_at,
  c.url as photo_url, c.credit as photo_credit, p.awards
from public.places p
left join lateral public.place_public_commons(p.id) c on true
where p.status = 'published';
grant select on public.places_public to anon, authenticated;

-- get_place_details: add photo_url / photo_credit / awards to the teaser part.
do $$
declare src text;
begin
  select pg_get_functiondef('public.get_place_details(uuid)'::regprocedure) into src;
  if position('''awards''' in src) = 0 then
    src := replace(src, '''images'', v_images, ''tags'', v_tags,',
      '''images'', v_images, ''tags'', v_tags, ''awards'', to_jsonb(p.awards),
    ''photo_url'', case when v_unlocked then p.photo_url end, ''photo_credit'', case when v_unlocked then p.photo_credit end,');
    if position('''awards''' in src) = 0 then raise exception 'get_place_details: anchor not found'; end if;
    execute src;
  end if;
end $$;
