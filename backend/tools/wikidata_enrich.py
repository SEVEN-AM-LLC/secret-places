#!/usr/bin/env python3
"""
Enrich places from Wikidata (CC0) and Wikimedia Commons, and add Michelin-recognised restaurants.

  1. photos  — for OSM places: OSM tag `wikidata` → Wikidata P18 (image) → Commons thumbnail
               + author/licence. Only freely licensed files (CC0 / public domain / CC BY / CC BY-SA);
               the credit is stored next to the photo and must be shown with it.
  2. awards  — Wikidata P166 'Michelin star' (Q20824563) / 'Bib Gourmand' (Q104135230) /
               "The World's 50 Best Restaurants" (Q2918929). Award statements with an end date, and
               closed restaurants, are skipped. Restaurants within 10 km of one of our cities that we
               don't have yet are added as paid 'food' places (sold through the city pass).

Reads places from the DB over SSH (read-only), writes a SQL migration:
  python3 backend/tools/wikidata_enrich.py OUT.sql

Sources: Wikidata (query.wikidata.org, www.wikidata.org), Commons (commons.wikimedia.org),
OSM tags via the OSM API (api.openstreetmap.org). Never use Russian-hosted services.
"""
import csv, hashlib, html, io, json, math, re, subprocess, sys, time, urllib.parse, urllib.request

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import world_import as w  # noqa: E402  (city list, Overpass mirrors, helpers)

UA = "SecretPlaces/1.0 (place enrichment; hello@7am.agency)"
SSH = ["ssh", "ubuntu@51.195.148.252"]
AWARDS = {"Q20824563": "michelin_star", "Q104135230": "bib_gourmand", "Q2918929": "worlds_50_best"}
FREE_LICENCE = re.compile(r"^(cc0|public domain|pd\b|pd-|cc[ -]by(-sa)?[ -]\d)", re.I)


def get(url: str, data: dict | None = None, tries: int = 4):
    body = urllib.parse.urlencode(data).encode() if data else None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read())
        except Exception as ex:
            print(f"  retry {i + 1}: {str(ex)[:80]}", file=sys.stderr)
            time.sleep(5 * (i + 1))
    raise RuntimeError(f"failed: {url}")


def db_places() -> list[dict]:
    sql = ("copy (select p.id, p.source_ref, p.business_name, p.exact_lat, p.exact_lng, p.wikidata, c.slug "
           "from places p left join cities c on c.id = p.city_id where p.source = 'openstreetmap') to stdout with csv header")
    out = subprocess.run(SSH + [f'sudo docker exec supabase-db psql -U postgres -c "{sql}"'], capture_output=True, text=True, check=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def osm_wikidata(places: list[dict]) -> dict[str, str]:
    """place id → wikidata QID, via the OSM element the place was imported from (OSM API multi-fetch)."""
    by_ref = {p["source_ref"]: p for p in places if p["source_ref"] and not p["wikidata"]}
    refs, found = list(by_ref), {}
    for kind in ("nodes", "ways"):
        for i in range(0, len(refs), 200):
            try:
                data = get(f"https://api.openstreetmap.org/api/0.6/{kind}.json?{kind}={','.join(refs[i:i + 200])}", tries=2)
            except RuntimeError:
                data = None
            if data is None:   # 404 when any id is missing: fall back to one by one is too chatty — halve instead
                for j in range(i, min(i + 200, len(refs)), 25):
                    try:
                        part = get(f"https://api.openstreetmap.org/api/0.6/{kind}.json?{kind}={','.join(refs[j:j + 25])}", tries=1)
                        (data := data or {"elements": []})["elements"] += part.get("elements", [])
                    except RuntimeError:
                        pass
            for e in (data or {}).get("elements", []):
                p, t = by_ref.get(str(e["id"])), e.get("tags", {})
                # node and way ids overlap: trust the element whose name matches what we imported
                if p and p["id"] not in found and t.get("wikidata") and (t.get("name") or "\0") in (p["business_name"] or ""):
                    found[p["id"]] = t["wikidata"].split(";")[0].strip()
            print(f"  osm {kind} {min(i + 200, len(refs))}/{len(refs)}: {len(found)} with wikidata", file=sys.stderr)
            time.sleep(1)
    return found


def entities(qids: list[str]) -> dict[str, dict]:
    out = {}
    for i in range(0, len(qids), 50):
        r = get("https://www.wikidata.org/w/api.php", {"action": "wbgetentities", "ids": "|".join(qids[i:i + 50]),
                                                        "props": "claims", "format": "json"})
        out.update(r.get("entities", {}))
        time.sleep(0.5)
    return out


def claim_image(ent: dict) -> str | None:
    for c in ent.get("claims", {}).get("P18", []):
        v = c.get("mainsnak", {}).get("datavalue", {}).get("value")
        if v and c.get("rank") != "deprecated":
            return v
    return None


def claim_awards(ent: dict) -> list[str]:
    out = []
    for c in ent.get("claims", {}).get("P166", []):
        qid = c.get("mainsnak", {}).get("datavalue", {}).get("value", {}).get("id")
        if qid in AWARDS and "P582" not in c.get("qualifiers", {}) and c.get("rank") != "deprecated":
            out.append(AWARDS[qid])
    return sorted(set(out))


def strip_html(s: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s or ""))).strip()


def commons(files: list[str]) -> dict[str, tuple[str, str]]:
    """file name → (thumbnail url, 'Photo: Author · CC BY-SA 4.0 · Wikimedia Commons')."""
    out = {}
    for i in range(0, len(files), 40):
        titles = "|".join("File:" + f for f in files[i:i + 40])
        r = get("https://commons.wikimedia.org/w/api.php", {"action": "query", "titles": titles, "prop": "imageinfo",
                                                             "iiprop": "url|extmetadata|mime", "iiurlwidth": "1000", "format": "json"})
        norm = {n["to"]: n["from"] for n in r.get("query", {}).get("normalized", [])}
        for page in r.get("query", {}).get("pages", {}).values():
            ii = (page.get("imageinfo") or [None])[0]
            if not ii or ii.get("mime") not in ("image/jpeg", "image/png", "image/webp"):
                continue
            md = ii.get("extmetadata", {})
            lic = strip_html(md.get("LicenseShortName", {}).get("value", ""))
            if not FREE_LICENCE.match(lic):
                continue
            artist = strip_html(md.get("Artist", {}).get("value", ""))
            # "No machine-readable author provided. Jane~commonswiki assumed (based on copyright claims)."
            if m := re.search(r"provided\. (.+?)(?:~commonswiki)? assumed", artist):
                artist = m.group(1)
            artist = re.sub(r"^Anonymous\s*Unknown author$", "Unknown author", artist)[:80] or "Unknown author"
            name = norm.get(page["title"], page["title"]).removeprefix("File:")
            out[name] = (ii.get("thumburl") or ii["url"], f"Photo: {artist} · {lic} · Wikimedia Commons")
        time.sleep(0.5)
    return out


def michelin() -> list[dict]:
    q = """SELECT ?r ?rLabel ?enLabel ?c ?img ?site ?a WHERE {
      VALUES ?a { wd:Q20824563 wd:Q104135230 wd:Q2918929 }
      ?r p:P166 ?st . ?st ps:P166 ?a . ?r wdt:P625 ?c .
      FILTER NOT EXISTS { ?st pq:P582 ?end } FILTER NOT EXISTS { ?r wdt:P576 ?d } FILTER NOT EXISTS { ?r wdt:P3999 ?d2 }
      OPTIONAL { ?r wdt:P18 ?img } OPTIONAL { ?r wdt:P856 ?site }
      OPTIONAL { ?r rdfs:label ?enLabel FILTER(LANG(?enLabel)="en") }
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul,fr,de,es,it,ja,pt,nl". }
    }"""
    rows = get("https://query.wikidata.org/sparql", {"query": q, "format": "json"})["results"]["bindings"]
    cities = [w.KYIV] + w.CITIES + w.EUROPE_2 + w.WORLD_3 + w.WORLD_4
    dist = lambda a, b, c, d: 6371 * 2 * math.asin(math.sqrt(math.sin(math.radians(c - a) / 2) ** 2 + math.cos(math.radians(a))
                                                             * math.cos(math.radians(c)) * math.sin(math.radians(d - b) / 2) ** 2))
    out: dict[str, dict] = {}
    for b in rows:
        lng, lat = map(float, b["c"]["value"].removeprefix("Point(").rstrip(")").split())
        qid = b["r"]["value"].rsplit("/", 1)[1]
        city = next((c for c in cities if dist(lat, lng, c[5], c[6]) < 10), None)
        if not city or re.fullmatch(r"Q\d+", (b.get("enLabel") or b["rLabel"])["value"]):
            continue
        e = out.setdefault(qid, {"qid": qid, "name": (b.get("enLabel") or b["rLabel"])["value"], "lat": lat, "lng": lng, "city": city,
                                 "img": urllib.parse.unquote(b["img"]["value"].rsplit("/", 1)[1]) if "img" in b else None,
                                 "site": b.get("site", {}).get("value"), "awards": set()})
        e["awards"].add(AWARDS[b["a"]["value"].rsplit("/", 1)[1]])
    return list(out.values())


FOOD_TITLES = ["A table the Michelin inspectors found first", "A Michelin-recognised kitchen worth the trip",
               "Dinner the critics still talk about", "A tasting menu the city is proud of"]
FOOD_DESCS = ["Book ahead, arrive hungry, and let the kitchen decide.",
              "One of the few rooms in the city where every plate is an event.",
              "Recognised by the Michelin Guide — the address is the secret."]


def q(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"


def main(out_path: str):
    places = db_places()
    print(f"{len(places)} OSM places in the DB", file=sys.stderr)
    place_qid = {p["id"]: p["wikidata"] for p in places if p["wikidata"]}
    place_qid.update(osm_wikidata(places))
    print(f"{len(place_qid)} places linked to Wikidata", file=sys.stderr)

    rest = michelin()
    known_qids = set(place_qid.values())
    new_rest = [r for r in rest if r["qid"] not in known_qids]
    print(f"{len(rest)} awarded restaurants near our cities, {len(new_rest)} new", file=sys.stderr)

    ents = entities(sorted(known_qids))
    images = {qid: claim_image(e) for qid, e in ents.items()}
    files = sorted({f for f in images.values() if f} | {r["img"] for r in new_rest if r["img"]})
    photos = commons(files)
    print(f"{len(photos)} freely licensed Commons photos", file=sys.stderr)

    sql = ["-- Generated by backend/tools/wikidata_enrich.py — Wikidata (CC0) + Wikimedia Commons (credited).",
           "-- Awards from Wikidata P166; photos keep their author/licence in photo_credit."]
    n_photo = n_award = 0
    for pid, qid in sorted(place_qid.items()):
        ent = ents.get(qid, {})
        photo = photos.get(images.get(qid) or "")
        awards = claim_awards(ent)
        sets = [f"wikidata={q(qid)}"]
        if photo:
            sets += [f"photo_url={q(photo[0])}", f"photo_credit={q(photo[1])}"]; n_photo += 1
        if awards:
            sets.append("awards=" + q("{" + ",".join(awards) + "}") + "::text[]"); n_award += 1
        sql.append(f"update public.places set {', '.join(sets)} where id='{pid}';")

    for r in new_rest:
        cslug, ctitle = r["city"][3], r["city"][4]
        country = f"(select id from public.countries where slug='{r['city'][0]}')"
        city = f"(select id from public.cities where slug='{cslug}' and country_id={country})"
        slug = f"{cslug}-{w.slugify(r['name']) or 'restaurant'}-{hashlib.md5(r['qid'].encode()).hexdigest()[:6]}"
        photo = photos.get(r["img"] or "")
        h = w.h(slug)
        label = {"michelin_star": "Michelin star", "bib_gourmand": "Bib Gourmand", "worlds_50_best": "The World's 50 Best Restaurants"}
        fd = (f"{r['name']}. Recognised with: {', '.join(label[a] for a in sorted(r['awards']))} (per Wikidata — check the current "
              f"guide before booking). In {ctitle}.")
        status = (f"(select case when exists (select 1 from public.places where city_id={city} and status='published') "
                  f"then 'published' else 'draft' end)")
        sql.append(
            "insert into public.places (slug,teaser_title,teaser_description,full_title,full_description,exact_lat,exact_lng,approx_lat,"
            "approx_lng,exact_address,business_name,website,walking_instructions,apple_maps_url,google_maps_url,country_id,city_id,"
            "primary_category_id,access_type,price_cents,product_id,status,travel_time_min,recommended_transport,best_time,best_season,"
            "expected_duration_min,crowd_level,price_level,mobile_signal,source,source_ref,wikidata,photo_url,photo_credit,awards)\n"
            f"select {q(slug)},{q(FOOD_TITLES[h % len(FOOD_TITLES)])},{q(FOOD_DESCS[h // 7 % len(FOOD_DESCS)])},{q(r['name'])},{q(fd)},"
            f"{r['lat']},{r['lng']},{round(r['lat'], 2)},{round(r['lng'], 2)},{q(ctitle)},{q(r['name'])},{q(r['site'])},"
            f"'Book ahead — tables go weeks in advance.','https://maps.apple.com/?ll={r['lat']},{r['lng']}',"
            f"'https://www.google.com/maps/search/?api=1&query={r['lat']},{r['lng']}',{country},{city},"
            f"(select id from public.categories where slug='food_drink'),'paid',{w.PASS_PRICE_CENTS},null,{status},15,'walk','evening',"
            f"'all year',120,'medium',4,'good','wikidata',{q(r['qid'])},{q(r['qid'])},{q(photo[0] if photo else None)},"
            f"{q(photo[1] if photo else None)},{q('{' + ','.join(sorted(r['awards'])) + '}')}::text[]\n"
            f"where exists (select 1 from public.cities where slug='{cslug}' and country_id={country})\non conflict (slug) do nothing;")
    open(out_path, "w").write("\n".join(sql) + "\n")
    print(f"wrote {out_path}: {n_photo} photos, {n_award} awards on existing places, {len(new_rest)} new restaurants", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "wikidata_enrich.sql")
