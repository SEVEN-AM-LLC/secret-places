#!/usr/bin/env python3
"""World importer: turns (country, city, centre) into Secret Places SQL from OpenStreetMap.

Hybrid curation — OSM supplies real, verifiable venues; the importer keeps only the kinds of
place the app is about and ranks them by quality signals (website, opening hours, Wikidata):

  paid (sold through the CITY PASS, no per-place App Store product):
    speakeasy / cocktail bars, rooftop bars, night clubs, and every third viewpoint
  free:
    the other viewpoints, notable historic sites (Wikidata), murals, gardens, specialty coffee

Categories are looked up by slug and cities by (country, slug), so the SQL is portable
between databases. Each city with paid places gets a pass product id
com.secretplaces.city.<slug>.

Usage:
  python3 backend/tools/world_import.py OUT.sql [city-slug ...]   # default: all CITIES
Data © OpenStreetMap contributors (ODbL).
"""
import hashlib, json, re, sys, time, unicodedata, urllib.parse, urllib.request

# Overpass mirrors — EU only. Never use Russian-hosted services.
MIRRORS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.private.coffee/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter"]
UA = "SecretPlaces/1.0 (city import; hello@7am.agency)"
RADIUS = 6000
PASS_PRICE_CENTS = 499

# (country slug, country name, flag, city slug, city title, lat, lng)
CITIES = [
    ("ukraine", "Ukraine", "🇺🇦", "lviv", "Lviv", 49.8397, 24.0297),
    ("ukraine", "Ukraine", "🇺🇦", "odesa", "Odesa", 46.4825, 30.7233),
    ("ukraine", "Ukraine", "🇺🇦", "kharkiv", "Kharkiv", 49.9935, 36.2304),
    ("ukraine", "Ukraine", "🇺🇦", "dnipro", "Dnipro", 48.4647, 35.0462),
    ("ukraine", "Ukraine", "🇺🇦", "vinnytsia", "Vinnytsia", 49.2331, 28.4682),
    ("ukraine", "Ukraine", "🇺🇦", "ivano-frankivsk", "Ivano-Frankivsk", 48.9226, 24.7111),
    ("portugal", "Portugal", "🇵🇹", "lisbon", "Lisbon", 38.7223, -9.1393),
    ("spain", "Spain", "🇪🇸", "barcelona", "Barcelona", 41.3874, 2.1686),
    ("france", "France", "🇫🇷", "paris", "Paris", 48.8566, 2.3522),
    ("germany", "Germany", "🇩🇪", "berlin", "Berlin", 52.5200, 13.4050),
    ("netherlands", "Netherlands", "🇳🇱", "amsterdam", "Amsterdam", 52.3676, 4.9041),
    ("czechia", "Czechia", "🇨🇿", "prague", "Prague", 50.0755, 14.4378),
    ("italy", "Italy", "🇮🇹", "rome", "Rome", 41.9028, 12.4964),
    ("turkiye", "Türkiye", "🇹🇷", "istanbul", "Istanbul", 41.0082, 28.9784),
    ("united-kingdom", "United Kingdom", "🇬🇧", "london", "London", 51.5074, -0.1278),
    ("georgia", "Georgia", "🇬🇪", "tbilisi", "Tbilisi", 41.7151, 44.8271),
]

# kind -> (category slug, cap per city)
KINDS = {
    "speakeasy": ("bars", 15), "rooftop": ("rooftops", 8), "night": ("night", 8), "viewpoint": ("viewpoints", 10),
    "historic": ("architecture", 12), "landmark": ("culture", 8), "mural": ("culture", 8), "garden": ("walks", 8),
    "coffee": ("coffee", 12),
}
PAID_KINDS = {"speakeasy", "rooftop", "night"}

TEASERS = {
    "speakeasy": (["A drink behind an unmarked door", "A bar the regulars keep quiet about", "A low-lit room that doesn't advertise",
                   "A cocktail bar you only find by asking", "The nightcap spot that isn't on the map", "A bar that trusts you to find it"],
                  ["No sign shouting for attention — just a door, and people who already know.",
                   "Small, unhurried, and better the later it gets.",
                   "Ask the right people and they'll send you here.",
                   "A short menu, a long memory, and nobody in a hurry to leave.",
                   "You have to know it's there — then it's the easiest place in the city to stay too long."]),
    "rooftop": (["A rooftop the city keeps to itself", "Drinks above the skyline", "A terrace most people never find",
                 "Golden hour, one floor below the sky"],
                ["Take the lift most people don't notice and the whole city opens up.",
                 "Come before sunset and stay for the lights.",
                 "Above the noise, with a view worth the climb."]),
    "night": (["A night that starts after midnight", "A club you find by asking", "A room that runs till sunrise",
               "Sound, concrete and a crowd who already know"],
              ["No frontage, no list online — just the people who know.",
               "Come late, leave early — in the morning.",
               "The door is the hard part; the rest takes care of itself."]),
    "viewpoint": (["A view over the city most people miss", "The overlook locals save for golden hour",
                   "A quiet ledge with a very loud view", "Where the city lays itself out below"],
                  ["Climb a little and the whole district unfolds — if you know where to stand.",
                   "Come at dusk and watch the rooftops catch the last light.",
                   "Everyone walks past the turn — take it, and look up."]),
    "historic": (["A piece of the city's story, hiding in plain sight", "A landmark the tours rush past",
                  "Old stones with a better story than the guidebook", "A corner of history worth slowing down for"],
                 ["Most people walk straight past — stop, and it starts talking.",
                  "Off the main route, and all the better for it.",
                  "Small, quiet, and older than everything around it."]),
    "landmark": (["A local landmark with a better story than the sign", "A corner of the city worth slowing down for",
                  "The place locals take visiting friends", "Something the city is quietly proud of"],
                 ["Go early, before the crowds, and it feels like yours.",
                  "Most people rush past — give it ten minutes.",
                  "Small detail, long history, worth the short detour."]),
    "mural": (["A wall worth the detour", "Street art you'll only spot if you look up", "The mural locals point friends to"],
              ["Turn the corner and there it is — bigger than you expected.",
               "A wall most people walk straight past.",
               "Find it yourself and it feels like yours."]),
    "garden": (["A green pocket to slow down in", "A garden most people rush past", "A quiet loop away from the crowds"],
               ["Trees, a path, and room to breathe five minutes from the noise.",
                "Come with a coffee and stay longer than you planned.",
                "Enough green to forget you're in the middle of the city."]),
    "coffee": (["A specialty coffee spot down a side street", "The pour-over place friends whisper about",
                "A tiny café that takes coffee seriously"],
               ["A few seats, a good roast, and mornings that stretch.",
                "Tucked away, but the espresso is why people keep coming back.",
                "Blink and you'd miss the door — don't."]),
}
SPEAKEASY_RX = re.compile(r"speak ?easy|secret|hidden|clandestin|unmarked|backroom|apothe|alchem|cocktail", re.I)
HISTORIC_OK = {"building", "castle", "monument", "ruins", "city_gate", "fort", "manor", "archaeological_site",
               "tower", "palace", "citywalls", "church", "monastery", "aqueduct", "bridge"}
GENERIC_WORDS = {"bar", "speakeasy", "cocktail", "cocktails", "the", "club", "rooftop", "cafe", "coffee", "lounge", "and", "wine"}
ROOFTOP_RX = re.compile(r"roof|rooftop|terrace|terraza|terrasse|sky|360|panoram", re.I)


def h(s: str) -> int:
    return int(hashlib.md5(s.encode()).hexdigest(), 16)


def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:36]


def esc(s):
    return s.replace("'", "''") if s else s


def overpass(lat: float, lng: float) -> list[dict]:
    r = f"(around:{RADIUS},{lat},{lng})"
    q = f"""[out:json][timeout:90];(
      node["tourism"="viewpoint"]["name"]{r};
      node["amenity"="bar"]["name"]{r};
      node["amenity"="nightclub"]["name"]{r};
      node["rooftop"="yes"]["name"]{r};
      node["amenity"="cafe"]["cuisine"~"coffee"]["name"]{r};
      node["tourism"="artwork"]["artwork_type"="mural"]["name"]{r};
      node["historic"]["name"]["wikidata"]{r};
      node["leisure"="garden"]["name"]{r};
      node["tourism"="attraction"]["name"]["wikidata"]{r};
    );out body;"""
    data = urllib.parse.urlencode({"data": q}).encode()
    for attempt in range(3):
        for m in MIRRORS:
            try:
                req = urllib.request.Request(m, data=data, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=120) as resp:
                    els = json.loads(resp.read()).get("elements", [])
                if els:
                    return [e for e in els if e.get("tags", {}).get("name") and "lat" in e]
            except Exception as ex:
                print(f"  mirror {m.split('/')[2]} failed: {str(ex)[:80]}", file=sys.stderr)
                time.sleep(3)
        time.sleep(15 * (attempt + 1))
    return []


def kind_of(t: dict) -> str | None:
    name = t.get("name", "")
    blob = " ".join([name, t.get("description", ""), t.get("bar", "")])
    if t.get("amenity") == "nightclub":
        return "night"
    if t.get("rooftop") == "yes" or (t.get("amenity") in ("bar", "restaurant") and ROOFTOP_RX.search(name)):
        return "rooftop"
    if t.get("amenity") == "bar" and (SPEAKEASY_RX.search(blob) or t.get("cocktails") == "yes" or t.get("drink:cocktail") in ("yes", "served")):
        return "speakeasy"
    if t.get("tourism") == "viewpoint":
        return "viewpoint"
    if t.get("tourism") == "artwork":
        return "mural"
    if t.get("historic") in HISTORIC_OK and t.get("wikidata"):
        return "historic"
    if t.get("tourism") == "attraction" and t.get("wikidata"):
        return "landmark"
    if t.get("leisure") == "garden":
        return "garden"
    if t.get("amenity") == "cafe":
        return "coffee"
    return None


def quality(t: dict) -> int:
    return (3 if t.get("wikidata") else 0) + (2 if (t.get("website") or t.get("contact:website")) else 0) \
        + (1 if t.get("opening_hours") else 0) + (1 if t.get("addr:street") else 0)


def pick(elements: list[dict], city_slug: str) -> list[tuple[str, dict]]:
    by_kind: dict[str, list[dict]] = {k: [] for k in KINDS}
    seen: list[tuple[str, float, float]] = []
    for e in sorted(elements, key=lambda e: -quality(e["tags"])):
        k = kind_of(e["tags"])
        if not k:
            continue
        # "Red Frog - Speakeasy Bar" and "Red Frog Speakeasy" 50 m apart are one place
        core = "-".join(w for w in slugify(e["tags"]["name"]).split("-") if w not in GENERIC_WORDS) or slugify(e["tags"]["name"])
        if any(core == c and abs(e["lat"] - la) < 0.004 and abs(e["lon"] - lo) < 0.004 for c, la, lo in seen):
            continue
        seen.append((core, e["lat"], e["lon"]))
        by_kind[k].append(e)
    out = []
    for k, (_, cap) in KINDS.items():
        ranked = sorted(by_kind[k], key=lambda e: (-quality(e["tags"]), h(f"{city_slug}{e['id']}")))
        out += [(k, e) for e in ranked[:cap]]
    return out


def city_sql(c) -> tuple[list[str], int, int]:
    country_slug, country_name, flag, cslug, ctitle, clat, clng = c
    picked = pick(overpass(clat, clng), cslug)
    if not picked:
        return [], 0, 0
    country = f"(select id from public.countries where slug='{country_slug}')"
    city = f"(select id from public.cities where slug='{cslug}' and country_id={country})"
    sql = [f"\n-- {ctitle}, {country_name}",
           f"insert into public.countries (slug,name,emoji_flag) values ('{country_slug}','{esc(country_name)}','{flag}') on conflict (slug) do nothing;",
           f"insert into public.cities (country_id,slug,title,lat,lng,is_outside_city) values ({country},'{cslug}','{esc(ctitle)}',{clat},{clng},false) "
           f"on conflict (country_id,slug) do nothing;"]
    vals, paid_n = [], 0
    for i, (k, e) in enumerate(picked):
        t = e["tags"]; name = t["name"]; lat, lng = e["lat"], e["lon"]
        slug = f"{cslug}-{slugify(name) or k}-{hashlib.md5(str(e['id']).encode()).hexdigest()[:6]}"
        titles, descs = TEASERS[k]
        tt, td = titles[h(slug) % len(titles)], descs[h(slug + 'd') % len(descs)]
        paid = k in PAID_KINDS or (k == "viewpoint" and h(slug + "p") % 3 == 0)
        paid_n += paid
        addr = (t["addr:street"] + (" " + t["addr:housenumber"] if t.get("addr:housenumber") else "") + f", {ctitle}") if t.get("addr:street") else ctitle
        website = t.get("website") or t.get("contact:website")
        oh = t.get("opening_hours")
        fd = f"{name}. " + (f"Find it at {addr}. " if t.get("addr:street") else f"In {ctitle}. ") + (f"Hours: {oh}. " if oh else "") + "Data © OpenStreetMap contributors."
        featured = "true" if (k in ("speakeasy", "viewpoint", "rooftop") and h(slug + "f") % 6 == 0) else "false"
        editors = "true" if quality(t) >= 4 and h(slug + "e") % 3 == 0 else "false"
        best_time = {"night": "night", "speakeasy": "evening", "rooftop": "sunset", "viewpoint": "sunset", "coffee": "morning", "landmark": "morning"}.get(k, "afternoon")
        duration = {"night": 240, "speakeasy": 90, "rooftop": 90, "coffee": 45}.get(k, 60)
        q = lambda v: f"'{esc(v)}'" if v else "null"
        vals.append(f"('{slug}','{esc(tt)}','{esc(td)}','{esc(name)}','{esc(fd)}',{lat},{lng},{round(lat, 2)},{round(lng, 2)},"
                    f"'{esc(addr)}','{esc(name)}',{q(website)},{q(oh)},'{KINDS[k][0]}','{'paid' if paid else 'free'}',"
                    f"{PASS_PRICE_CENTS if paid else 0},{featured},{editors},'{best_time}',{duration},'{e['id']}')")
    sql.append(
        "insert into public.places (slug,teaser_title,teaser_description,full_title,full_description,exact_lat,exact_lng,approx_lat,approx_lng,"
        "exact_address,business_name,website,opening_hours,walking_instructions,apple_maps_url,google_maps_url,country_id,city_id,primary_category_id,"
        "access_type,price_cents,product_id,status,featured,editors_choice,travel_time_min,recommended_transport,best_time,best_season,"
        "expected_duration_min,crowd_level,price_level,mobile_signal,source,source_ref)\n"
        "select v.slug,v.tt,v.td,v.ft,v.fd,v.lat,v.lng,v.alat,v.alng,v.addr,v.biz,v.ws,"
        "(case when v.oh is null then null else jsonb_build_object('raw',v.oh) end),"
        "'From the nearest stop it''s a short walk — look for the entrance, not a sign.',"
        "'https://maps.apple.com/?ll='||v.lat||','||v.lng,'https://www.google.com/maps/search/?api=1&query='||v.lat||','||v.lng,"
        f"{country},{city},(select id from public.categories where slug=v.cat),v.access,v.price,null,'published',v.featured,v.editors,"
        "15,'walk',v.best,'all year',v.dur,'medium',2,'good','openstreetmap',v.sref\nfrom (values\n" + ",\n".join(vals) +
        "\n) v(slug,tt,td,ft,fd,lat,lng,alat,alng,addr,biz,ws,oh,cat,access,price,featured,editors,best,dur,sref)\non conflict (slug) do nothing;")
    if paid_n:
        sql.append(f"update public.cities set pass_product_id='com.secretplaces.city.{cslug.replace('-', '_')}', pass_price_cents={PASS_PRICE_CENTS} "
                   f"where slug='{cslug}' and country_id={country};")
    return sql, len(picked), paid_n


if __name__ == "__main__":
    out_path = sys.argv[1] if len(sys.argv) > 1 else "world_seed.sql"
    only = set(sys.argv[2:])
    lines = ["-- Generated by backend/tools/world_import.py — real places from OpenStreetMap (ODbL), © OpenStreetMap contributors."]
    for c in CITIES:
        if only and c[3] not in only:
            continue
        sql, n, paid = city_sql(c)
        print(f"{c[4]:16s} {n:3d} places ({paid} paid via city pass)", flush=True)
        lines += sql
        time.sleep(5)  # be polite to the public Overpass mirrors
    open(out_path, "w").write("\n".join(lines) + "\n")
    print("wrote", out_path)
