-- City cover photos from Wikimedia Commons, with their credit. Separate from cover_url because
-- app 1.0.0 renders cover_url without a credit line; only 1.0.1+ reads these.
alter table public.cities
  add column if not exists cover_photo_url text,
  add column if not exists cover_photo_credit text;
