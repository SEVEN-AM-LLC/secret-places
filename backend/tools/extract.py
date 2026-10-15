"""
Fallback data source for world_import when the public Overpass mirrors are down: BBBike city extracts
(https://download.bbbike.org/osm/bbbike/, OSM data, ODbL), filtered locally with pyosmium.

Returns elements in Overpass JSON shape ({type, id, lat, lon, tags}) for the same tag selectors
world_import.SELECTORS asks Overpass for, within `radius` metres of the city centre.
Needs pyosmium (the importer's venv on the server); without it, or for a city BBBike doesn't have, returns None.
Each extract is downloaded once per run and deleted afterwards (they are 50–400 MB).
"""
import math, os, re, sys, unicodedata, urllib.request

LIST_URL = "https://download.bbbike.org/osm/bbbike/"
UA = "SecretPlaces/1.0 (city import fallback; hello@7am.agency)"
CACHE = os.environ.get("SP_EXTRACT_DIR", "/tmp/sp-extracts")
OVERRIDES = {   # our city slug → BBBike name, where the names differ
    "kyiv": "Kiew", "prague": "Prag", "vienna": "Wien", "munich": "Muenchen", "zurich": "Zuerich", "brussels": "Bruessel",
    "cologne": "Koeln", "ghent": "Gent", "krakow": "Cracow", "mumbai": "Bombay", "delhi": "NewDelhi",
    "ho-chi-minh-city": "Saigon", "rio-de-janeiro": "RiodeJaneiro", "washington": "WashingtonDC", "antwerp": "Antwerpen",
    "gothenburg": "Goeteborg", "turin": "Turin", "san-sebastian": "", "sao-paulo": "",
}
_names: set[str] | None = None


def _norm(s: str) -> str:
    return re.sub(r"[^A-Za-z]", "", unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode())


def bbbike_name(slug: str, title: str) -> str | None:
    global _names
    if _names is None:
        html = urllib.request.urlopen(urllib.request.Request(LIST_URL, headers={"User-Agent": UA}), timeout=60).read().decode()
        _names = set(re.findall(r'href="([A-Z][A-Za-z]*)/"', html))
    name = OVERRIDES.get(slug, _norm(title))
    return name if name in _names else None


def wanted(t, is_node: bool) -> bool:
    """The same selectors as world_import.SELECTORS."""
    if "name" not in t:
        return False
    g = lambda k: t.get(k)
    if g("tourism") == "museum" or g("amenity") == "marketplace" or g("natural") == "beach":
        return True
    if not is_node:
        return g("leisure") == "park" and "wikidata" in t
    return (g("tourism") == "viewpoint" or g("amenity") in ("bar", "nightclub") or g("rooftop") == "yes"
            or (g("amenity") == "cafe" and "coffee" in (g("cuisine") or ""))
            or (g("tourism") == "artwork" and g("artwork_type") == "mural")
            or ("historic" in t and "wikidata" in t) or g("leisure") == "garden"
            or (g("tourism") == "attraction" and "wikidata" in t)
            or (g("amenity") in ("restaurant", "pub") and "wikidata" in t)
            or g("shop") == "books")


def dist_m(a, b, c, d) -> float:
    return 6371000 * 2 * math.asin(math.sqrt(math.sin(math.radians(c - a) / 2) ** 2 + math.cos(math.radians(a))
                                              * math.cos(math.radians(c)) * math.sin(math.radians(d - b) / 2) ** 2))


def elements(slug: str, title: str, lat: float, lng: float, radius: float) -> list[dict] | None:
    try:
        import osmium
    except ImportError:
        return None
    name = bbbike_name(slug, title)
    if not name:
        print(f"  extract: BBBike has no {title}", file=sys.stderr)
        return None
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{name}.osm.pbf")
    req = urllib.request.Request(f"{LIST_URL}{name}/{name}.osm.pbf", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=600) as r, open(path, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    out = []
    try:
        fp = (osmium.FileProcessor(path, osmium.osm.NODE | osmium.osm.WAY).with_locations()
              .with_filter(osmium.filter.KeyFilter("name")))
        for o in fp:
            tags = dict(o.tags)
            if o.is_node():
                if not wanted(tags, True):
                    continue
                la, lo = o.location.lat, o.location.lon
                typ = "node"
            else:
                if not wanted(tags, False):
                    continue
                pts = [(n.location.lat, n.location.lon) for n in o.nodes if n.location.valid()]
                if not pts:
                    continue
                la, lo = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
                typ = "way"
            if dist_m(lat, lng, la, lo) <= radius:
                out.append({"type": typ, "id": o.id, "lat": la, "lon": lo, "tags": tags})
    finally:
        os.remove(path)
    print(f"  extract: {title} via BBBike {name}: {len(out)} elements", file=sys.stderr)
    return out
