// ============================================================
// Secret Places — verify-purchase Edge Function
// Verifies a StoreKit 2 signed transaction (JWS) and grants the
// corresponding entitlement server-side. Handles BOTH product kinds:
//   • a place product (com.secretplaces.place.<slug>) → unlock one place
//   • a route product (com.secretplaces.route.<slug>) → unlock a bar crawl
//     (and, transitively, every place it contains)
// Entitlements are the ONLY way a client obtains exact locations, so this
// function is the trust boundary. Transactions are verified with Apple's
// official library against Apple's root CA, accepting both Production and
// Sandbox (TestFlight / App Review) — see verify.ts. APPLE_VERIFY=dev skips
// signature checks and must only ever be used locally.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { configFromEnv, verifyTransaction, VerifyError } from "./verify.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CONFIG = configFromEnv((k) => Deno.env.get(k));

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const asUser = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData?.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  let body: { transactionJWS?: string; placeId?: string; routeSlug?: string };
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  if (!body.transactionJWS) return json({ error: "missing_transaction" }, 400);

  let tx: any;
  try { tx = await verifyTransaction(body.transactionJWS, CONFIG); }
  catch (e) {
    const code = e instanceof VerifyError ? e.code : "verification_failed";
    // Misconfiguration is our fault, not the client's — surface it as a 500.
    const status = code === "apple_root_certs_missing" || code === "apple_app_id_missing" ? 500
      : code === "verification_unavailable" ? 503 : 400;
    console.error("verify-purchase:", code, e instanceof VerifyError ? "" : String(e));
    return json({ error: code }, status);
  }

  const productId: string | undefined = tx.productId;
  const originalTransactionId: string | undefined = tx.originalTransactionId ?? tx.transactionId;
  const transactionId: string | undefined = tx.transactionId;
  const bundleId: string | undefined = tx.bundleId ?? tx.appBundleId;
  if (!productId || !transactionId) return json({ error: "incomplete_transaction" }, 400);
  if (CONFIG.strict && bundleId !== CONFIG.bundleId) return json({ error: "bundle_mismatch" }, 400);
  if (tx.revocationDate) return json({ error: "revoked" }, 400);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  // A signed transaction is a bearer token: stop one purchase from being replayed
  // to unlock content on other accounts. (Entitlements cascade-delete with the
  // account, so a deleted-and-recreated account can still restore.)
  if (originalTransactionId) {
    const { data: claimed, error: claimErr } = await admin.from("user_entitlements")
      .select("user_id").eq("original_transaction_id", originalTransactionId).neq("user_id", userId).limit(1);
    if (claimErr) return json({ error: "entitlement_error" }, 500);
    if (claimed && claimed.length > 0) return json({ error: "transaction_already_claimed" }, 409);
  }

  // 1) Place product?
  const { data: place } = await admin.from("places").select("id, product_id").eq("product_id", productId).maybeSingle();
  if (place) {
    const { error } = await admin.from("user_entitlements").upsert({
      user_id: userId, place_id: place.id, product_id: productId,
      transaction_id: transactionId, original_transaction_id: originalTransactionId,
      source: "app_store", revoked_at: null,
    }, { onConflict: "user_id,place_id,original_transaction_id" });
    if (error) { console.error("verify-purchase: upsert", error.message); return json({ error: "entitlement_error" }, 500); }
    const { data: details } = await asUser.rpc("get_place_details", { p_place_id: place.id });
    return json({ unlocked: true, kind: "place", place_id: place.id, place: details });
  }

  // 2) Route product? (bar crawl — unlocks all its stops)
  const { data: route } = await admin.from("routes").select("id, slug, product_id").eq("product_id", productId).maybeSingle();
  if (route) {
    const { data: existing } = await admin.from("user_entitlements")
      .select("id").eq("user_id", userId).eq("route_id", route.id).maybeSingle();
    if (!existing) {
      const { error } = await admin.from("user_entitlements").insert({
        user_id: userId, route_id: route.id, product_id: productId,
        transaction_id: transactionId, original_transaction_id: originalTransactionId,
        source: "app_store", revoked_at: null,
      });
      if (error) { console.error("verify-purchase: upsert", error.message); return json({ error: "entitlement_error" }, 500); }
    }
    const { data: details } = await asUser.rpc("get_route_details", { p_slug: route.slug });
    return json({ unlocked: true, kind: "route", route_id: route.id, route: details });
  }

  return json({ error: "unknown_product" }, 400);
});
