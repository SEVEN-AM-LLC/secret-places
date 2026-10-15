// Run: deno run --allow-read --allow-env --allow-net review_shots.ts  (expects ./review.png — a simulator screenshot of the Unlock screen)
// Attaches the same App Review screenshot (the in-app Unlock screen) to every IAP lacking one.
import { api } from "./asc.ts";
import { crypto as stdCrypto } from "jsr:@std/crypto@1";
// Optional arg: image path (default ./review.png); only IAPs without a review screenshot get one.
const file = await Deno.readFile(Deno.args[0] ?? new URL("./review.png", import.meta.url));
const md5 = Array.from(new Uint8Array(await stdCrypto.subtle.digest("MD5", file))).map((b) => b.toString(16).padStart(2, "0")).join("");
const iaps: any[] = [];
for (let next: string | undefined = "/v1/apps/6822694406/inAppPurchasesV2?limit=200&fields[inAppPurchases]=productId,state"; next; ) {
  const r = await api("GET", next); iaps.push(...r.data); next = r.links?.next;
}
for (const i of iaps) {
  try {
    const cur = await api("GET", `/v2/inAppPurchases/${i.id}/appStoreReviewScreenshot`).catch(() => null);
    if (cur?.data) { console.log(`skip ${i.attributes.productId}`); continue; }
    const res = await api("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", { data: { type: "inAppPurchaseAppStoreReviewScreenshots",
      attributes: { fileName: "unlock-screen.png", fileSize: file.byteLength },
      relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: i.id } } } } });
    for (const op of res.data.attributes.uploadOperations) {
      const headers: Record<string, string> = {};
      for (const h of op.requestHeaders ?? []) headers[h.name] = h.value;
      const r = await fetch(op.url, { method: op.method, headers, body: file.slice(op.offset, op.offset + op.length) });
      if (!r.ok) throw new Error(`upload part ${r.status}`);
    }
    await api("PATCH", `/v1/inAppPurchaseAppStoreReviewScreenshots/${res.data.id}`, { data: {
      type: "inAppPurchaseAppStoreReviewScreenshots", id: res.data.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } });
    console.log(`OK   ${i.attributes.productId}`);
  } catch (e) { console.log(`FAIL ${i.attributes.productId}: ${(e as Error).message}`); }
}
