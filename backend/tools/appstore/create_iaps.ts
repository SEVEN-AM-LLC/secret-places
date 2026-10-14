// Creates the app's non-consumable IAPs from the LIVE catalogue (places + routes),
// so App Store product IDs always match what verify-purchase looks up.
// Idempotent: products that already exist are completed, not duplicated.
// Run: SUPABASE_ANON_KEY=... deno run --allow-read --allow-env --allow-net create_iaps.ts [productId]
// Auth: ASC API key AuthKey_<KEY_ID>.p8 in ~/.appstoreconnect/private_keys (see asc.ts).
import { api } from "./asc.ts";
const APP = "6822694406";
const SB = "https://api.secretplaces.7am.agency/rest/v1";
const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? (() => { throw new Error("set SUPABASE_ANON_KEY (publishable key from ios/SecretPlaces/Core/Config.swift)"); })();
const sb = (q: string) => fetch(`${SB}/${q}`, { headers: { apikey: anon } }).then((r) => r.json());
const only = Deno.args[0]; // optional productId filter for a dry single run

// App Store product IDs allow only [A-Za-z0-9_.]; the DB is migrated to the same form (0029).
const appleId = (id: string) => id.replace(/-/g, "_");
type P = { productId: string; ref: string; name: string; desc: string; price: string };
const places = await sb("places_public?select=slug,product_id,price_cents&access_type=eq.paid&product_id=not.is.null");
const routes = await sb("routes_public?select=slug,title,product_id,price_cents,is_free&is_free=eq.false");
const cut = (s: string, n: number) => (s.length <= n ? s : s.slice(0, n - 1).trimEnd() + "…");
const products: P[] = [
  ...places.map((p: any) => ({ productId: p.product_id, ref: cut(`Place — ${p.slug}`, 64),
    name: "Unlock this secret place", desc: "Exact spot, directions and insider tips", price: (p.price_cents / 100).toFixed(2) })),
  ...routes.map((r: any) => ({ productId: r.product_id, ref: cut(`Route — ${r.title}`, 64),
    name: cut(r.title, 30), desc: "Self-guided route: every stop, in order", price: (r.price_cents / 100).toFixed(2) })),
].map((p) => ({ ...p, productId: appleId(p.productId) })).filter((p) => !only || p.productId === only);
console.log(`catalogue: ${products.length} products`);

// Every territory, so the products sell worldwide.
const territories: { type: string; id: string }[] = [];
for (let next: string | undefined = "/v1/territories?limit=200"; next; ) {
  const r = await api("GET", next); territories.push(...r.data.map((t: any) => ({ type: "territories", id: t.id }))); next = r.links?.next;
}
console.log(`territories: ${territories.length}`);

const existing = new Map<string, string>();
for (const i of (await api("GET", `/v1/apps/${APP}/inAppPurchasesV2?limit=200`)).data) existing.set(i.attributes.productId, i.id);

async function usdPricePoint(iapId: string, price: string): Promise<string> {
  for (let next: string | undefined = `/v2/inAppPurchases/${iapId}/pricePoints?filter[territory]=USA&limit=200`; next; ) {
    const r = await api("GET", next);
    const hit = r.data.find((pp: any) => pp.attributes.customerPrice === price);
    if (hit) return hit.id;
    next = r.links?.next;
  }
  throw new Error(`no USD price point ${price}`);
}

for (const p of products) {
  try {
    const id: string = existing.get(p.productId) ?? (await api("POST", "/v2/inAppPurchases", { data: { type: "inAppPurchases",
        attributes: { name: p.ref, productId: p.productId, inAppPurchaseType: "NON_CONSUMABLE", familySharable: false,
          reviewNote: "Unlocks the exact location and full guide for this item in the app. Sign in with Apple first, then tap Unlock." },
        relationships: { app: { data: { type: "apps", id: APP } } } } })).data.id;
    const locs = await api("GET", `/v2/inAppPurchases/${id}/inAppPurchaseLocalizations`);
    if (!locs.data.some((l: any) => l.attributes.locale === "en-US")) {
      await api("POST", "/v1/inAppPurchaseLocalizations", { data: { type: "inAppPurchaseLocalizations",
        attributes: { locale: "en-US", name: p.name, description: p.desc },
        relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id } } } } });
    }
    const pp = await usdPricePoint(id, p.price);
    await api("POST", "/v1/inAppPurchasePriceSchedules", {
      data: { type: "inAppPurchasePriceSchedules", relationships: {
        inAppPurchase: { data: { type: "inAppPurchases", id } },
        baseTerritory: { data: { type: "territories", id: "USA" } },
        manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${price0}" }] } } },
      included: [{ type: "inAppPurchasePrices", id: "${price0}", attributes: { startDate: null },
        relationships: { inAppPurchasePricePoint: { data: { type: "inAppPurchasePricePoints", id: pp } } } }] });
    await api("POST", "/v1/inAppPurchaseAvailabilities", { data: { type: "inAppPurchaseAvailabilities",
      attributes: { availableInNewTerritories: true },
      relationships: { inAppPurchase: { data: { type: "inAppPurchases", id } }, availableTerritories: { data: territories } } } });
    console.log(`OK   ${p.productId}  $${p.price}  (${id})`);
  } catch (e) {
    console.log(`FAIL ${p.productId}: ${(e as Error).message}`);
  }
}
