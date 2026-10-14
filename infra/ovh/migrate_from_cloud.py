#!/usr/bin/env python3
"""Replays the repo migrations on the self-hosted DB. Seeds create reference rows with
random UUIDs, while later migrations hard-code the UUIDs the cloud project happened to
get — so before each file, cloud UUIDs are rewritten to the local UUID of the row with
the same slug. Cloud ids/slugs are read via the public REST API (no DB password)."""
import json, os, re, subprocess, sys, urllib.request
MIG = sys.argv[1]
KEY = os.environ["ANON"]; U = "https://qovfroivqskzelpuxfwp.supabase.co/rest/v1/"
TABLES = {"countries": "countries", "regions": "regions", "cities": "cities", "neighborhoods": "neighborhoods",
          "categories": "categories", "collections": "collections", "routes": "routes_public", "places": "places_public"}
def cloud(t):
    req = urllib.request.Request(f"{U}{t}?select=id,slug&limit=5000", headers={"apikey": KEY})
    return json.load(urllib.request.urlopen(req))
cloud_ids = {local: {r["id"]: r["slug"] for r in cloud(remote)} for local, remote in TABLES.items()}
def psql(sql, single=False):
    flags = "-1 " if single else ""
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-i", os.path.expanduser("~/.ssh/id_rsa"), "ubuntu@51.195.148.252",
        f"sudo docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -At {flags}2>&1"],
        input=sql, capture_output=True, text=True)
def local_ids():
    existing = set(psql("select table_name from information_schema.tables where table_schema='public';").stdout.split())
    parts = [f"select '{t}', slug, id::text from public.{t}" for t in TABLES if t in existing]
    r = psql(" union all ".join(parts) + ";")
    m = {}
    for line in r.stdout.splitlines():
        p = line.split("|")
        if len(p) == 3: m.setdefault(p[0], {})[p[1]] = p[2]
    return m
order = ["0001", "0003", "0002", "0005", "0006", "0004"] + sorted({f[:4] for f in os.listdir(MIG) if f[:4].isdigit() and f[:4] >= "0007"})
START = sys.argv[2] if len(sys.argv) > 2 else "0000"
for n in order:
    if order.index(n) < order.index(START) if START in order else False: continue
    f = next(x for x in sorted(os.listdir(MIG)) if x.startswith(n + "_"))
    sql = open(os.path.join(MIG, f)).read()
    loc = local_ids()
    swaps = 0
    for t, ids in cloud_ids.items():
        for cid, slug in ids.items():
            lid = loc.get(t, {}).get(slug)
            if lid and lid != cid and cid in sql:
                sql = sql.replace(cid, lid); swaps += 1
    if n == "0021":  # cron should call the gateway on the docker network, not the cloud project
        sql = sql.replace("https://qovfroivqskzelpuxfwp.supabase.co/functions/v1/sync-events", "http://api-gw:8000/functions/v1/sync-events")
    leftover = [u for t in cloud_ids for u in cloud_ids[t] if u in sql and u not in {v for m in loc.values() for v in m.values()}]
    r = psql(sql, single=True)
    bad = r.returncode != 0 or "ERROR" in r.stdout
    print(f"{f:44s} {'FAIL' if bad else 'ok'}  (uuid swaps: {swaps}{', unresolved: %d' % len(leftover) if leftover else ''})")
    if bad:
        print("\n".join(l for l in r.stdout.splitlines() if "ERROR" in l or "DETAIL" in l)[:800]); sys.exit(1)
