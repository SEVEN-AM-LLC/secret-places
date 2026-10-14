# Secret Places — architecture

## Layers

```
SwiftUI Views ──▶ ViewModels (@MainActor) ──▶ Repositories (protocols)
                                              │
              AppEnvironment (DI container) ──┤── SupabaseClient (URLSession REST/RPC/Edge)
                                              │── AuthStore + TokenHolder (Sign in with Apple → Supabase)
                                              │── PurchaseService (StoreKit 2) ─▶ verify-purchase Edge Fn
                                              │── EntitlementService (server-synced, cached)
                                              └── LocationService (CoreLocation, optional)
                                                        │
                                              Supabase: Postgres + PostGIS, RLS, RPCs, Edge Functions
```

- **Modular by folder**: `App, Core, Networking, Domain, Auth, Location, Purchases, Features/*`.
- **Protocol-first services** (`PlaceRepository`, `GeoRepository`, `CategoryRepository`,
  `CollectionsRepository`, `SearchService`, `SavedPlacesRepository`, `EntitlementService`,
  `RatingsRepository`, `ReportsRepository`, `LocationServing`, `AuthServicing`) with Supabase
  implementations and in-memory mocks (`MockRepositories`) used by tests/previews.
- **DI** via `AppEnvironment`, injected through the SwiftUI environment — no ad-hoc singletons.
- **Async/await** throughout; **typed errors** (`AppError`); explicit
  loading/empty/error/offline states (`LoadState`).

## Key flows

- **Discover** loads featured / free-today / editor / newest rails + cities from `places_public`.
- **Place detail** calls `get_place_details`. Locked → teaser + approximate-area map + unlock CTA.
  Unlocked/free → full guide, exact map, Apple/Google Maps directions, tips, rate, report.
- **Unlock** → (require Sign in) → `PurchaseService.purchase` (StoreKit 2) → `verify-purchase`
  Edge Function verifies the JWS and writes the entitlement → detail re-fetched as unlocked and
  cached for offline.
- **Restore** re-syncs `Transaction.currentEntitlements` to the server. A `Transaction.updates`
  listener handles Ask-to-Buy approvals and refunds/revocations.
- **My Secrets**: Unlocked / Saved / Visited / Want-to-visit, synced per account.
- **Nearby** uses `nearby_places` (PostGIS KNN) with rounded distance; location is optional.

## Domain future-proofing (not built, but unblocked)

The domain layer is structured so an **AI travel concierge**, **paid collections**, a
**subscription tier**, **creator submissions/moderation**, a **web app** and a
**recommendation engine** can be added without breaking changes: collections already carry
price/product fields; `user_entitlements` references both `place_id` and `collection_id`;
`submissions` has a moderation state machine; categories are backend-configured.

## Remaining configuration (external)

1. **Apple Developer**: set `DEVELOPMENT_TEAM` + a real bundle id; enable the Sign in with Apple
   capability (entitlement already declared).
2. **Supabase Auth → Apple provider**: add the Services ID + Sign in with Apple key so the
   `id_token` exchange in `AuthStore` succeeds.
3. **App Store Connect**: create the non-consumable IAP products matching
   `com.secretplaces.place.<slug>` ($0.99) — the seeded products are listed in
   `ios/SecretPlaces/Support/SecretPlaces.storekit`.
4. **Purchase verification**: `verify-purchase` always verifies the JWS signature + cert chain
   with `@apple/app-store-server-library` and accepts both Production and Sandbox (TestFlight /
   App Review) transactions. It needs `APPLE_ROOT_CERTS` (AppleRootCA-G3) and `APPLE_APP_ID`
   set as function secrets; without them it fails closed (500). `APPLE_VERIFY=dev` is local-only.
5. **Push notifications**: APNs key + a scheduler for "Free Secret Today" / nearby alerts
   (preferences table + UI already exist).

## Next development phase

Real photography + image storage (Supabase Storage buckets) · web editorial CMS on the same
schema · paid collections & a subscription tier · AI concierge over the catalog · richer
map clustering · push notifications · localization · analytics provider behind the existing
`AnalyticsService` abstraction.
