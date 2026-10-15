#!/usr/bin/env python3
"""
More freely licensed photos for places (and city covers), on top of wikidata_enrich.py.

  1. OSM tags  — `wikimedia_commons=File:…`, `image=` (Commons links only), `wikipedia=lang:Title`
                 (→ the article's lead image), and Wikidata places without P18 (→ their Wikipedia article).
  2. Nearby    — Commons files geotagged within 60 m of a free outdoor/cultural place, kept only when the
                 file name carries a distinctive word of the place's name (so we never show the building next door).
  3. Cities    — a lead image of the city's English Wikipedia article (checked against the city's coordinates).

Every photo goes through wikidata_enrich.commons(): JPEG/PNG/WebP, CC0 / PD / CC BY / CC BY-SA only,
stored with "Photo: author · licence · Wikimedia Commons". Writes a SQL migration:
  python3 backend/tools/photos_more.py OUT.sql
"""
import csv, io, math, re, subprocess, sys, time, unicodedata, urllib.parse

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import wikidata_enrich as we  # noqa: E402

NEARBY_CATS = {"viewpoints", "walks", "culture", "architecture", "nature", "beaches", "underground"}
STOP = {"the", "and", "park", "parc", "parque", "garden", "gardens", "jardin", "jardim", "view", "viewpoint", "miradouro",
        "mirador", "street", "square", "place", "plaza", "piazza", "platz", "church", "museum", "cafe", "coffee", "house",
        "city", "old", "new", "saint", "santa", "san", "santo", "sankt", "with", "from", "mural", "monument", "statue",
        "tower", "bridge", "gate", "hall", "palace", "castle", "castello", "chateau", "kirche", "igreja", "iglesia", "eglise"}


def sql_rows(sql: str) -> list[dict]:
    out = subprocess.run(we.SSH + [f'sudo docker exec supabase-db psql -U postgres -c "copy ({sql}) to stdout with csv header"'],
                         capture_output=True, text=True, check=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def words(s: str) -> set[str]:
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return {w for w in re.split(r"[^a-z0-9]+", s) if len(w) >= 4 and w not in STOP and not w.isdigit()}


def osm_tags(places: list[dict]) -> dict[str, dict]:
    """place id → OSM tags of the element it was imported from (name-checked: node and way ids overlap)."""
    by_ref = {p["source_ref"]: p for p in places if p["source_ref"]}
    refs, found = list(by_ref), {}
    for kind in ("nodes", "ways"):
        for i in range(0, len(refs), 100):
            try:
                data = we.get(f"https://api.openstreetmap.org/api/0.6/{kind}.json?{kind}={','.join(refs[i:i + 100])}", tries=2)
            except RuntimeError:   # 404 when any id doesn't exist as this kind — retry in small chunks
                data = {"elements": []}
                for j in range(i, min(i + 100, len(refs)), 20):
                    try:
                        data["elements"] += we.get(f"https://api.openstreetmap.org/api/0.6/{kind}.json?{kind}={','.join(refs[j:j + 20])}", tries=1)["elements"]
                    except RuntimeError:
                        pass
            for e in data.get("elements", []):
                p, t = by_ref.get(str(e["id"])), e.get("tags", {})
                if p and p["id"] not in found and (t.get("name") or "\0") in (p["business_name"] or ""):
                    found[p["id"]] = t
            print(f"  osm {kind} {min(i + 100, len(refs))}/{len(refs)}", file=sys.stderr)
            time.sleep(1)
    return found


def commons_file(v: str) -> str | None:
    """A Commons file name from an OSM image/wikimedia_commons value, or None (other hosts: licence unknown)."""
    v = urllib.parse.unquote((v or "").split(";")[0].strip())
    if v.startswith("File:"):
        return v[5:]
    m = re.search(r"commons\.wikimedia\.org/wiki/File:(.+)$", v) or re.search(r"upload\.wikimedia\.org/wikipedia/commons/(?:thumb/)?\w/\w\w/([^/]+)", v)
    return m.group(1).replace("_", " ") if m else None


def lead_images(titles: dict[str, str]) -> dict[str, tuple[str, float | None, float | None]]:
    """{key: 'lang:Title'} → {key: (file, lat, lng)} via the article's free lead image (pageimages)."""
    by_lang: dict[str, dict[str, str]] = {}
    for key, wt in titles.items():
        lang, _, title = wt.partition(":")
        if title and re.fullmatch(r"[a-z\-]{2,12}", lang):
            by_lang.setdefault(lang, {})[title.replace("_", " ")] = key
    out = {}
    for lang, m in by_lang.items():
        ts = list(m)
        for i in range(0, len(ts), 40):
            try:
                r = we.get(f"https://{lang}.wikipedia.org/w/api.php", {"action": "query", "titles": "|".join(ts[i:i + 40]),
                           "prop": "pageimages|coordinates", "piprop": "name", "pilicense": "free", "redirects": 1, "format": "json"})
            except RuntimeError:
                continue
            q = r.get("query", {})
            alias = {n["to"]: n["from"] for n in q.get("normalized", []) + q.get("redirects", [])}
            for page in q.get("pages", {}).values():
                if not page.get("pageimage"):
                    continue
                t = page["title"]
                while t in alias and t not in m:
                    t = alias[t]
                if t in m:
                    c = (page.get("coordinates") or [{}])[0]
                    out[m[t]] = (page["pageimage"].replace("_", " "), c.get("lat"), c.get("lon"))
            time.sleep(0.5)
    return out


CITY_WORDS: set[str] = set()   # filled in main(): city/district names match too many unrelated files


def nearby_file(name: str, lat: float, lng: float) -> str | None:
    want = words(name) - CITY_WORDS
    if not want:
        return None
    # Two-word names need both words ("Tauschgarten Perlach" is not any building in Perlach); longer names most of them.
    need = len(want) if len(want) <= 2 else math.ceil(len(want) * 0.6)
    try:
        r = we.get("https://commons.wikimedia.org/w/api.php", {"action": "query", "list": "geosearch", "gscoord": f"{lat}|{lng}",
                   "gsradius": 60, "gsnamespace": 6, "gslimit": 30, "format": "json"}, tries=2)
    except RuntimeError:
        return None
    for hit in r.get("query", {}).get("geosearch", []):
        title = hit["title"].removeprefix("File:")
        if len(want & words(title)) >= need and re.search(r"\.(jpe?g|png|webp)$", title, re.I):
            return title
    return None


def dist_km(a, b, c, d):
    return 6371 * 2 * math.asin(math.sqrt(math.sin(math.radians(c - a) / 2) ** 2 + math.cos(math.radians(a)) * math.cos(math.radians(c))
                                         * math.sin(math.radians(d - b) / 2) ** 2))


def main(out_path: str):
    places = sql_rows("select p.id, p.source_ref, p.business_name, p.exact_lat, p.exact_lng, p.wikidata, cat.slug cat "
                      "from places p left join categories cat on cat.id = p.primary_category_id "
                      "where p.source = 'openstreetmap' and p.photo_url is null and p.hero_image_url is null")
    cities = sql_rows("select id, title, lat, lng from cities where cover_photo_url is null and lat is not null")
    print(f"{len(places)} places without a photo, {len(cities)} cities without a cover", file=sys.stderr)
    for c in sql_rows("select title from cities"):
        CITY_WORDS.update(words(c["title"]))
    CITY_WORDS.update({"leith", "perlach", "athens", "athina", "lisboa", "roma", "praha", "wien", "munchen", "firenze", "napoli", "kyiv", "kiev"})

    tags = osm_tags(places)
    files: dict[str, str] = {}      # place id → Commons file name
    wiki: dict[str, str] = {}       # place id → 'lang:Title'
    for pid, t in tags.items():
        f = commons_file(t.get("wikimedia_commons", "")) or commons_file(t.get("image", ""))
        if f:
            files[pid] = f
        elif t.get("wikipedia"):
            wiki[pid] = t["wikipedia"]
    # Wikidata items without an image of their own: try their Wikipedia article's lead image.
    need_wd = {p["id"]: (p["wikidata"] or tags.get(p["id"], {}).get("wikidata", "").split(";")[0].strip())
               for p in places if p["id"] not in files and p["id"] not in wiki}
    need_wd = {k: v for k, v in need_wd.items() if re.fullmatch(r"Q\d+", v or "")}
    for i in range(0, len(need_wd), 50):
        ids = list(dict.fromkeys(list(need_wd.values())[i:i + 50]))
        r = we.get("https://www.wikidata.org/w/api.php", {"action": "wbgetentities", "ids": "|".join(ids), "props": "sitelinks", "format": "json"})
        for pid, qid in list(need_wd.items())[i:i + 50]:
            sl = r.get("entities", {}).get(qid, {}).get("sitelinks", {})
            for lang in ("en", "fr", "de", "es", "it", "pt", "nl", "pl", "uk", "cs"):
                if f"{lang}wiki" in sl:
                    wiki[pid] = f"{lang}:{sl[f'{lang}wiki']['title']}"; break
        time.sleep(0.5)
    for pid, (f, _, _) in lead_images(wiki).items():
        files.setdefault(pid, f)
    print(f"tags/wikipedia: {len(files)} candidate files", file=sys.stderr)

    by_id = {p["id"]: p for p in places}
    near = [p for p in places if p["id"] not in files and p["cat"] in NEARBY_CATS]
    for n, p in enumerate(near, 1):
        f = nearby_file(p["business_name"], float(p["exact_lat"]), float(p["exact_lng"]))
        if f:
            files[p["id"]] = f
        if n % 100 == 0:
            print(f"  nearby {n}/{len(near)}: {len(files)} candidates", file=sys.stderr)
        time.sleep(0.2)

    covers = {}
    for c, (f, la, lo) in lead_images({c["id"]: f"en:{c['title']}" for c in cities}).items():
        city = next(x for x in cities if x["id"] == c)
        if la is None or dist_km(float(city["lat"]), float(city["lng"]), la, lo) < 40:   # not some other Santiago
            covers[c] = f

    photos = we.commons(sorted(set(files.values()) | set(covers.values())))
    sql = ["-- Generated by backend/tools/photos_more.py — Wikimedia Commons photos via OSM tags, Wikipedia lead images",
           "-- and geotagged files named after the place. Credits travel with each photo."]
    n_p = n_c = 0
    for pid, f in sorted(files.items()):
        if f in photos:
            url, credit = photos[f]
            sql.append(f"update public.places set photo_url={we.q(url)}, photo_credit={we.q(credit)} where id='{pid}' and photo_url is null;")
            n_p += 1
    for cid, f in sorted(covers.items()):
        if f in photos:
            url, credit = photos[f]
            sql.append(f"update public.cities set cover_photo_url={we.q(url)}, cover_photo_credit={we.q(credit)} where id='{cid}';")
            n_c += 1
    open(out_path, "w").write("\n".join(sql) + "\n")
    print(f"wrote {out_path}: {n_p} place photos, {n_c} city covers", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "photos_more.sql")
