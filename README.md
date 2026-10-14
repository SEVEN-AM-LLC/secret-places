# Secret Places 🗺️

A native iOS app for discovering unusual, hidden and curated locations around the world.
Some places are **free**; premium places unlock for **$0.99**. Before unlocking, the app
deliberately hides everything that would reveal the exact place — and that hiding is
**enforced server-side**, not just in the UI.

- **iOS**: Swift · SwiftUI · iOS 18+ · Swift Concurrency · MapKit · CoreLocation · StoreKit 2 · Sign in with Apple
- **Backend**: Supabase (Postgres + PostGIS) · RLS on all user data · Edge Functions for the trust boundary

The backend is **self-hosted on OVH** (`https://api.secretplaces.7am.agency`, see `infra/ovh/README.md`) and the app runs on the iOS 18/26
simulator against it. See the final report and `docs/SECURITY.md`.

---

## The core idea: server-enforced privacy

A paid place's exact latitude/longitude, address, business name and directions **never leave
the database** for a non-entitled user. This is guaranteed by three layers:

1. **`places_public` view** exposes teaser columns only (approximate coords).
2. **Column-level privileges** on the base `places` table: teaser columns are granted to
   `anon`/`authenticated`; the sensitive columns are **not granted**, so any query touching them —
   including `select=*` — returns `permission denied`. RLS additionally limits rows to `published`.
3. **`get_place_details(uuid)`** is the only path to full data. It checks the entitlement
   (`is_place_unlocked`) and returns the sensitive fields **only when the place is free/promo or
   the user owns an entitlement**; otherwise it returns the teaser with `locked: true`.

Entitlements are written **only** by the `verify-purchase` Edge Function after verifying a
StoreKit 2 transaction — never by the client. See `docs/SECURITY.md` for the passing acceptance test.

---

## Repository layout

```
SecretPlaces/
├─ backend/supabase/
│  ├─ migrations/   0001 schema · 0003 functions · 0002 RLS · 0005 hardening · 0006 revoke · 0004 seed
│  └─ functions/    verify-purchase/ (StoreKit trust boundary) · delete-account/
├─ ios/
│  ├─ project.yml               (XcodeGen)
│  ├─ SecretPlaces/
│  │  ├─ App/ Core/ Networking/ Domain/ Auth/ Location/ Purchases/ Features/ Support/
│  │  └─ Support/SecretPlaces.storekit
│  └─ SecretPlacesTests/        (19 unit tests)
└─ docs/                        ARCHITECTURE · SECURITY · SCHEMA
```

## Run the iOS app

```bash
cd ios
xcodegen generate                       # brew install xcodegen
open SecretPlaces.xcodeproj
# or headless:
xcodebuild build -project SecretPlaces.xcodeproj -scheme SecretPlaces \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild test  -project SecretPlaces.xcodeproj -scheme SecretPlaces \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The Supabase URL + anon key are baked into `Core/Config.swift` (the anon key is publishable).
To test purchases, attach `SecretPlaces/Support/SecretPlaces.storekit` to the scheme
(Edit Scheme → Run → Options → StoreKit Configuration).

## Backend (already applied to the live project)

Apply order for a fresh database (0003 before 0002 — RLS references a function):

```bash
psql "$DATABASE_URL" -f backend/supabase/migrations/0001_init_schema.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0003_functions.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0002_rls_and_public_view.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0005_hardening.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0006_revoke_internal_fn_public.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0004_seed.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0007_place_source.sql
psql "$DATABASE_URL" -f backend/supabase/migrations/0008_real_places_osm.sql
supabase functions deploy verify-purchase
supabase functions deploy delete-account
```

## What's implemented (MVP)

Discover · Search · Cities · Neighborhoods · Places (locked & unlocked) · Free places ·
$0.99 unlocks (StoreKit 2) · Map (approx pins for locked) · Nearby (CoreLocation, optional) ·
Saved / Visited / Want-to-visit / Unlocked ("My Secrets") · Sign in with Apple · guest browsing ·
restore purchases · server-protected paid data · collections · offline access to unlocked places ·
ratings · report a place · onboarding interests · notification preferences · account deletion.

## Remaining external configuration

See the final report / `docs/ARCHITECTURE.md` §"Remaining configuration": Apple Developer team &
bundle id, Sign in with Apple key wired into Supabase Auth, App Store Connect IAP products, and
`APPLE_ROOT_CERTS` + `APPLE_APP_ID` secrets on the `verify-purchase` function (it verifies
Production and Sandbox transactions and fails closed without them).

## Data attribution

Seeded place data is derived from **OpenStreetMap** and is © **OpenStreetMap
contributors**, under the **Open Database License (ODbL)**
(https://www.openstreetmap.org/copyright). See `backend/supabase/DATA_SOURCES.md`.
