#!/usr/bin/env python3
"""
Nightly place import — keeps every city growing without anyone running scripts by hand.

Each run takes the N cities imported longest ago (never-imported first), re-imports them from OpenStreetMap
(world_import --deepen: only new places are added; a city with published places gets them published, a draft
city keeps them as drafts), then enriches just the new places: Wikidata/Commons photos and awards, more Commons
photos, and teasers that don't repeat the city's existing ones.

Runs on the OVH host (systemd timer, see infra/ovh/importer/), talking to the local Supabase DB:
  SP_DB=local SP_STATE=/opt/secretplaces-importer/state.json python3 autopilot.py
Env: SP_CITIES_PER_RUN (default 8), SP_RECENT_DAYS (default 2).
New cities still need their city-pass IAP created and approved before publishing (backend/tools/appstore).
"""
import datetime as dt, json, os, sys, tempfile, time, traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import db, world_import as w, wikidata_enrich as we, photos_more as pm, teasers as tz  # noqa: E402

STATE = os.environ.get("SP_STATE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "autopilot_state.json"))
PER_RUN = int(os.environ.get("SP_CITIES_PER_RUN", "8"))
RECENT = int(os.environ.get("SP_RECENT_DAYS", "2"))


def log(*a):
    print(dt.datetime.now().strftime("%H:%M:%S"), *a, flush=True)


def counts() -> dict:
    return {r["status"]: int(r["n"]) for r in db.rows("select status, count(*) n from places group by 1")}


def step(name: str, fn):
    """Generate a migration into a temp file with one of the enrich tools, then apply it."""
    try:
        with tempfile.NamedTemporaryFile("r", suffix=".sql") as f:
            fn(f.name)
            sql = open(f.name).read()
        n = sql.count("\n") - 2
        if n > 0:
            db.apply(sql)
        log(f"{name}: {max(n, 0)} statements applied")
    except Exception:
        log(f"{name}: FAILED\n{traceback.format_exc()}")


def main():
    state = json.load(open(STATE)) if os.path.exists(STATE) else {}
    cities = [w.KYIV] + w.CITIES + w.EUROPE_2 + w.WORLD_3 + w.WORLD_4 + w.WORLD_5 + w.WORLD_6
    priority = {c[3] for c in w.WORLD_6}   # revenue picks jump the queue among never-imported cities
    queue = sorted(cities, key=lambda c: (state.get(c[3], ""), c[3] not in priority))[:PER_RUN]   # never-run first, then oldest
    before = counts()
    log(f"start: {before}; cities this run: {', '.join(c[4] for c in queue)}")

    w.DEEPEN = True
    for c in queue:
        try:
            sql, n, paid = w.city_sql(c)
            if sql:
                db.apply("\n".join(sql))
                log(f"{c[4]}: {n} candidates from OSM ({paid} paid)")
            else:
                log(f"{c[4]}: Overpass returned nothing — will retry next run")
                continue
            state[c[3]] = dt.datetime.now(dt.timezone.utc).isoformat()
            json.dump(state, open(STATE, "w"), indent=1)
        except Exception:
            log(f"{c[4]}: FAILED\n{traceback.format_exc()}")
        time.sleep(5)   # be polite to the public Overpass mirrors

    we.RECENT_DAYS = pm.RECENT_DAYS = tz.RECENT_DAYS = RECENT
    step("wikidata photos + awards", we.main)
    step("more Commons photos", pm.main)
    step("teasers", tz.main)

    after = counts()
    log(f"done: {after}; new published {after.get('published', 0) - before.get('published', 0)}, "
        f"new drafts {after.get('draft', 0) - before.get('draft', 0)}")
    waiting = db.rows("select c.title from cities c where c.pass_product_id is not null "
                      "and not public.city_has_published_places(c.id) order by 1")
    if waiting:
        log(f"draft cities waiting for their pass + publish ({len(waiting)}): {', '.join(r['title'] for r in waiting)}")


if __name__ == "__main__":
    main()
