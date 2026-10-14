// Minimal App Store Connect API client (ES256 JWT via WebCrypto).
const KEY_ID = "AQWQ32CFFH";
const ISSUER = "a753e4ef-028b-4b9a-9978-95d0e80fa16b";
const pem = await Deno.readTextFile(`${Deno.env.get("HOME")}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`);
const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
const b64u = (b: Uint8Array | string) => btoa(typeof b === "string" ? b : String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
let token = "", exp = 0;
async function jwt() {
  const now = Math.floor(Date.now() / 1000);
  if (token && now < exp - 60) return token;
  exp = now + 15 * 60;
  const head = b64u(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }));
  const body = b64u(JSON.stringify({ iss: ISSUER, iat: now, exp, aud: "appstoreconnect-v1" }));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${body}`)));
  return (token = `${head}.${body}.${b64u(sig)}`);
}
export async function api(method: string, path: string, body?: unknown): Promise<any> {
  const url = path.startsWith("http") ? path : `https://api.appstoreconnect.apple.com${path}`;
  for (let attempt = 0; ; attempt++) {
    let r: Response;
    try {
      r = await fetch(url, { method, headers: { Authorization: `Bearer ${await jwt()}`, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
    } catch (e) {
      if (attempt < 5) { await new Promise((s) => setTimeout(s, 3000 * (attempt + 1))); continue; } // transient network error
      throw e;
    }
    if (r.status === 429 && attempt < 5) { await new Promise((s) => setTimeout(s, 2000 * (attempt + 1))); continue; }
    const text = await r.text();
    const json = text ? JSON.parse(text) : {};
    if (!r.ok) throw new Error(`${method} ${path} -> ${r.status}: ${JSON.stringify(json.errors ?? json).slice(0, 8000)}`);
    return json;
  }
}
