// ============================================================
// Secret Places — enrich-photos Edge Function (Google Places, New)
// Backfills places.hero_image_url with REAL venue photos from the Google
// Places API (New). Never fabricates: a place is updated only when Google
// returns a confident match (close by + name overlap) that HAS a photo.
// No match / no photo → left null (the app shows a neutral placeholder,
// never a stock photo of a different place).
//
// We store Google's resolved googleusercontent photo URL (via
// photos/media?skipHttpRedirect=true) — NOT a URL containing the API key,
// so the key never reaches the client. Google requires photo attribution;
// authorAttributions are captured for display.
//
// Trigger: POST with x-sync-secret (SYNC_SECRET env, service-role key, or the
// Vault secret used by pg_cron). Body: { limit?, onlyPaid?, redo?, dryRun? }.
// Requires GOOGLE_PLACES_KEY (env) or Vault secret google_places_key.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SYNC_SECRET = Deno.env.get("SYNC_SECRET") ?? "";
let GKEY = Deno.env.get("GOOGLE_PLACES_KEY") ?? "";

const G_BASE = "https://places.googleapis.com/v1";
const PHOTO_MAXH = Deno.env.get("G_PHOTO_MAXH") ?? "900";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-sync-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Cyrillic (uk/ru) → Latin, so a Cyrillic venue name compares against Google's
// Latin transliteration (Коньякотека ↔ Konyakoteka, Дос Амигос ↔ Dos Amigos).
const CYR: Record<string, string> = {
  а:"a",б:"b",в:"v",г:"h",ґ:"g",д:"d",е:"e",є:"ie",ж:"zh",з:"z",и:"y",і:"i",ї:"i",
  й:"i",к:"k",л:"l",м:"m",н:"n",о:"o",п:"p",р:"r",с:"s",т:"t",у:"u",ф:"f",х:"kh",
  ц:"ts",ч:"ch",ш:"sh",щ:"shch",ь:"",ю:"iu",я:"ia",ъ:"",ы:"y",э:"e",ё:"e",
};
function translit(s: string): string {
  let out = "";
  for (const ch of (s || "").toLowerCase()) out += CYR[ch] ?? ch;
  return out;
}
// Normalise to lowercase latin alnum words (after transliteration).
function norm(s: string): string {
  return translit(s)
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
function tokens(s: string): Set<string> {
  return new Set(norm(s).split(" ").filter((t) => t.length >= 2));
}
// Same-venue check. Candidates are already location-restricted to ~150m, so a
// moderate token overlap is safe; transliteration bridges the scripts.
function nameMatches(a: string, b: string): boolean {
  const na = norm(a), nb = norm(b);
  if (!na || !nb) return false;
  if (na === nb) return true;
  // Substring only when the shorter side is specific enough (>=4 chars).
  if (na.length >= 4 && nb.includes(na)) return true;
  if (nb.length >= 4 && na.includes(nb)) return true;
  const ta = tokens(a), tb = tokens(b);
  let shared = 0;
  for (const t of ta) if (tb.has(t)) shared++;
  if (shared === 0) return false;
  // Cover at least half of the query's tokens (proximity carries the rest).
  return shared / (ta.size || 1) >= 0.5;
}
// Drop a bilingual parenthetical: "Module (Модуль)" → "Module".
function cleanQuery(name: string): string {
  return name.replace(/\s*[(（].*?[)）]\s*/g, " ").replace(/\s+/g, " ").trim() || name;
}

type GPlace = { displayName?: { text?: string }; location?: { latitude: number; longitude: number }; photos?: any[] };

function metres(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6_371_000, toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat), dLng = toRad(bLng - aLng);
  const s = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

async function gSearch(name: string, lat: number, lng: number, radius: number): Promise<GPlace[]> {
  // Location BIAS (not restrict): tolerant of slightly-off stored coords, so a
  // real venue is still found. A same-named business in another district is
  // rejected afterwards by the distance gate on the returned location.
  const res = await fetch(`${G_BASE}/places:searchText`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": GKEY,
      "X-Goog-FieldMask": "places.displayName,places.location,places.photos",
    },
    body: JSON.stringify({
      textQuery: name,
      maxResultCount: 5,
      locationBias: { circle: { center: { latitude: lat, longitude: lng }, radius } },
    }),
  });
  if (!res.ok) throw new Error(`search ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const body = await res.json();
  return (body.places ?? []) as GPlace[];
}

// Resolve a photo resource name → stable googleusercontent url (no key).
async function gPhotoUrl(photoName: string): Promise<string | null> {
  const u = `${G_BASE}/${photoName}/media?maxHeightPx=${PHOTO_MAXH}&skipHttpRedirect=true`;
  const res = await fetch(u, { headers: { "X-Goog-Api-Key": GKEY } });
  if (!res.ok) return null;
  const body = await res.json().catch(() => null);
  return body?.photoUri ?? null;
}
function attribution(photo: any): string | null {
  const a = photo?.authorAttributions?.[0]?.displayName;
  return a ? String(a) : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const db = createClient(SUPABASE_URL, SERVICE_ROLE);

  const provided = req.headers.get("x-sync-secret") ?? "";
  let authed = (SYNC_SECRET && provided === SYNC_SECRET) || (provided !== "" && provided === SERVICE_ROLE);
  if (!authed && provided !== "") {
    const { data: ok } = await db.rpc("check_sync_secret", { p: provided });
    authed = ok === true;
  }
  if (!authed) return json({ error: "unauthorized" }, 401);

  if (!GKEY) {
    const { data: k } = await db.rpc("get_enrich_key", { p_name: "google_places_key" });
    if (typeof k === "string") GKEY = k;
  }
  if (!GKEY) return json({ error: "missing Google key (env GOOGLE_PLACES_KEY or Vault google_places_key)" }, 500);

  const opts = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(opts.limit ?? 40), 1), 120);
  const radius = Math.min(Math.max(Number(opts.radius ?? 400), 40), 2000);   // search bias radius
  const maxDist = Math.min(Math.max(Number(opts.maxDist ?? 350), 60), 1500);  // reject matches farther than this
  const dryRun = opts.dryRun === true;

  let query = db.from("places")
    .select("id, slug, business_name, full_title, exact_lat, exact_lng, access_type")
    .not("exact_lat", "is", null)
    .not("exact_lng", "is", null)
    .order("access_type", { ascending: true })
    .limit(limit);
  if (opts.redo !== true) query = query.is("hero_image_url", null);
  if (opts.onlyPaid === true) query = query.eq("access_type", "paid");
  const { data: places, error } = await query;
  if (error) return json({ error: String(error.message) }, 500);
  if (!places || places.length === 0) return json({ ok: true, considered: 0, updated: 0, note: "nothing to enrich" });

  let matched = 0, updated = 0, noMatch = 0, noPhoto = 0, errors = 0;
  const samples: any[] = [];

  for (const p of places) {
    const name = (p.business_name || p.full_title || "").trim();
    if (!name) { noMatch++; continue; }
    try {
      const results = await gSearch(cleanQuery(name), p.exact_lat, p.exact_lng, radius);
      // Same name AND physically here (distance gate rejects far homonyms).
      const cand = results.find((r) => {
        if (!nameMatches(name, r.displayName?.text ?? "")) return false;
        const loc = r.location;
        if (!loc) return true; // no coords back → trust the name+bias
        return metres(p.exact_lat, p.exact_lng, loc.latitude, loc.longitude) <= maxDist;
      }) ?? null;
      const gname = cand?.displayName?.text ?? results[0]?.displayName?.text ?? null;
      if (!cand) { noMatch++; if (samples.length < 14) samples.push({ slug: p.slug, name, got: gname, matched: false }); continue; }
      const photo = (cand.photos ?? [])[0];
      if (!photo?.name) { noPhoto++; if (samples.length < 14) samples.push({ slug: p.slug, name, g: gname, photo: null }); continue; }
      matched++;
      const url = await gPhotoUrl(photo.name);
      if (!url) { noPhoto++; if (samples.length < 14) samples.push({ slug: p.slug, name, g: gname, photo: null }); continue; }
      if (samples.length < 14) samples.push({ slug: p.slug, name, g: gname, photo: url, by: attribution(photo) });
      if (!dryRun) {
        const { error: uerr } = await db.from("places").update({ hero_image_url: url }).eq("id", p.id);
        if (uerr) { errors++; continue; }
      }
      updated++;
    } catch (_e) {
      errors++;
      if (samples.length < 14) samples.push({ slug: p.slug, name, error: String(_e).slice(0, 160) });
    }
  }

  return json({ ok: true, considered: places.length, matched, updated, noMatch, noPhoto, errors, dryRun, samples });
});
