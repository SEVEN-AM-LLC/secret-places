-- ============================================================
-- Stop republishing third-party event media.
-- Posters and description texts come from the organisers' sites (Concert.ua,
-- Resident Advisor, theatre pages) and we hold no licence for them. The app now
-- shows only facts (title, date, venue, price, lineup) plus a link to tickets.
-- The columns stay in the table (the sync keeps filling them) but are no longer
-- exposed; same column list/types so old app builds keep decoding the view.
-- ============================================================
create or replace view public.events_public with (security_invoker = true) as
select e.id, e.slug, e.title, null::text as description, e.kind, e.starts_at, e.ends_at,
  null::text as poster_url, e.ticket_url, e.price_from_cents, e.currency, e.is_free, e.lineup,
  e.featured, e.city_id, e.place_id,
  coalesce(e.venue_name, p.teaser_title) as venue_teaser,
  coalesce(e.venue_lat, p.approx_lat) as venue_approx_lat,
  coalesce(e.venue_lng, p.approx_lng) as venue_approx_lng,
  p.primary_category_id as venue_category, p.access_type as venue_access,
  e.venue_name
from public.events e
left join public.places p on p.id = e.place_id and p.status = 'published'
where e.status = 'published' and coalesce(e.ends_at, e.starts_at) >= now() - interval '6 hours';
grant select on public.events_public to anon, authenticated;
