# Secret Places — database migrations

Apply in order to a Postgres 15+ database with the Supabase extensions available:

```
0001_init_schema.sql          -- extensions, geo hierarchy, places (+sensitive/teaser split), all tables, indexes, geog trigger
0003_functions.sql            -- is_place_unlocked, can_rate_place, get_place_details (entitlement gate), nearby_places, rating aggregate, handle_new_user
0002_rls_and_public_view.sql  -- places_public teaser view + RLS on every table
0005_hardening.sql            -- column-level privileges on places, security_invoker view, place_categories RLS, search_path
0006_revoke_internal_fn_public.sql -- revoke internal SECURITY DEFINER helpers from PUBLIC
0004_seed.sql                 -- development seed (Ukraine → Kyiv → neighborhoods + places, a collection)
seed_admin.sql                -- (not present here) demo moderation rows — n/a for Secret Places
```

Note: 0002 depends on functions from 0003 (RLS policy calls can_rate_place), so apply 0003 before 0002 — this mirrors the deployed order (see version timestamps).

Originally applied to the Supabase cloud project; now replayed onto the self-hosted stack on OVH (see infra/ovh/README.md).
