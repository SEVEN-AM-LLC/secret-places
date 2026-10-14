# Data tools

## world_import.py — add any city in the world

Turns a list of `(country, city, center lat/lng)` into curated Secret Places
SQL from OpenStreetMap (viewpoints, bars, coffee, parks, street art), with the
same teaser/privacy model and varied teaser copy. The platform's country →
city → neighborhood hierarchy and PostGIS proximity are already global; this
just supplies data.

```bash
python3 backend/tools/world_import.py out.sql [city-slug ...]   # default: every city in CITIES
# apply on the OVH stack (see infra/ovh/README.md), then create the new city passes:
SUPABASE_ANON_KEY=... deno run -A backend/tools/appstore/create_iaps.ts com.secretplaces.city.<slug>
deno run -A backend/tools/appstore/review_shots.ts backend/tools/appstore/review-city-pass.png
```

Edit the `CITIES` list to add destinations; paid places there are sold through the city pass. Data © OpenStreetMap contributors (ODbL).
Overpass mirrors are rate-limited/occasionally down; the fetch retries across
mirrors. Re-run when a mirror is available.
