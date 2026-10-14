-- ============================================================
-- App Store product IDs may contain only letters, digits, "_" and "." —
-- the OSM-imported places used hyphenated slugs (com.secretplaces.place.krysha-933879),
-- which App Store Connect rejects, so those products could never be sold.
-- The IAPs were created in App Store Connect with "-" → "_"; bring the catalogue
-- (and any existing unlock records) in line, and stop invalid IDs coming back.
-- ============================================================
update public.places set product_id = replace(product_id, '-', '_') where product_id like '%-%';
update public.routes set product_id = replace(product_id, '-', '_') where product_id like '%-%';
update public.user_entitlements set product_id = replace(product_id, '-', '_') where product_id like '%-%';

alter table public.places add constraint places_product_id_apple_format
  check (product_id is null or product_id ~ '^[A-Za-z0-9_.]+$');
alter table public.routes add constraint routes_product_id_apple_format
  check (product_id is null or product_id ~ '^[A-Za-z0-9_.]+$');
