-- Expand beyond Kyiv: add major Ukrainian cities and wire a Concert.ua
-- (jsonld) events source for each. Concert.ua carries real listings for all
-- of them (concerts, stand-up, theatre, shows).
with ua as (select id from public.countries where slug = 'ukraine' limit 1)
insert into public.cities (country_id, slug, title, lat, lng, cover_url)
select ua.id, c.slug, c.title, c.lat, c.lng,
  'https://picsum.photos/seed/spc-' || c.slug || '/800/500?grayscale'
from ua, (values
  ('lviv','Lviv',49.8397,24.0297),
  ('odesa','Odesa',46.4825,30.7233),
  ('kharkiv','Kharkiv',49.9935,36.2304),
  ('dnipro','Dnipro',48.4647,35.0462),
  ('vinnytsia','Vinnytsia',49.2331,28.4682),
  ('ivano-frankivsk','Ivano-Frankivsk',48.9226,24.7111)
) as c(slug,title,lat,lng)
on conflict (country_id, slug) do nothing;

insert into public.event_sources (provider, label, kind, city_slug, config)
select 'jsonld', 'Concert.ua — ' || initcap(c.slug), 'concert', c.slug,
  jsonb_build_object('url', 'https://concert.ua/uk/city/' || c.slug)
from (values ('lviv'),('odesa'),('kharkiv'),('dnipro'),('vinnytsia'),('ivano-frankivsk')) as c(slug)
where not exists (
  select 1 from public.event_sources s
  where s.provider='jsonld' and s.config->>'url' = 'https://concert.ua/uk/city/' || c.slug
);
