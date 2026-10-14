// Pushes the App Store listing (appstore/metadata.json + appstore/<locale>/*.png) to the
// version that is in "Prepare for Submission". Idempotent: updates what exists, creates
// what's missing, and replaces the 6.9" screenshot set.
// Run: deno run --allow-read --allow-env --allow-net upload_listing.ts
import { api } from "./asc.ts";
import { crypto as stdCrypto } from "jsr:@std/crypto@1";

const APP = "6822694406";
const VERSION = "1.0.0"; // must match CFBundleShortVersionString (MARKETING_VERSION)
const root = new URL("../../../appstore/", import.meta.url);
const meta = JSON.parse(await Deno.readTextFile(new URL("metadata.json", root)));

// --- App info: categories + per-locale name/subtitle/privacy URL
const info = (await api("GET", `/v1/apps/${APP}/appInfos`)).data.find((i: any) => i.attributes.state !== "READY_FOR_DISTRIBUTION") ??
  (await api("GET", `/v1/apps/${APP}/appInfos`)).data[0];
await api("PATCH", `/v1/appInfos/${info.id}`, { data: { type: "appInfos", id: info.id, relationships: {
  primaryCategory: { data: { type: "appCategories", id: meta.app.primaryCategory } },
  secondaryCategory: { data: { type: "appCategories", id: meta.app.secondaryCategory } } } } });
const infoLocs = (await api("GET", `/v1/appInfos/${info.id}/appInfoLocalizations`)).data;
for (const [locale, l] of Object.entries<any>(meta.localizations)) {
  const attrs = { name: l.name, subtitle: l.subtitle, privacyPolicyUrl: meta.app.privacyPolicyUrl };
  const cur = infoLocs.find((x: any) => x.attributes.locale === locale);
  if (cur) await api("PATCH", `/v1/appInfoLocalizations/${cur.id}`, { data: { type: "appInfoLocalizations", id: cur.id, attributes: attrs } });
  else await api("POST", "/v1/appInfoLocalizations", { data: { type: "appInfoLocalizations", attributes: { locale, ...attrs },
    relationships: { appInfo: { data: { type: "appInfos", id: info.id } } } } });
  console.log(`app info ${locale}: ok`);
}

// --- Version: number, copyright, per-locale listing text
const version = (await api("GET", `/v1/apps/${APP}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION`)).data[0];
if (!version) throw new Error("no iOS version in Prepare for Submission");
await api("PATCH", `/v1/appStoreVersions/${version.id}`, { data: { type: "appStoreVersions", id: version.id,
  attributes: { versionString: VERSION, copyright: meta.app.copyright } } });
console.log(`version ${version.attributes.versionString} -> ${VERSION}`);
const verLocs = (await api("GET", `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`)).data;
const locIds: Record<string, string> = {};
for (const [locale, l] of Object.entries<any>(meta.localizations)) {
  const attrs = { description: l.description, keywords: l.keywords, promotionalText: l.promotionalText,
    supportUrl: meta.app.supportUrl, marketingUrl: meta.app.marketingUrl };
  const cur = verLocs.find((x: any) => x.attributes.locale === locale);
  locIds[locale] = cur
    ? (await api("PATCH", `/v1/appStoreVersionLocalizations/${cur.id}`, { data: { type: "appStoreVersionLocalizations", id: cur.id, attributes: attrs } })).data.id
    : (await api("POST", "/v1/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations", attributes: { locale, ...attrs },
        relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version.id } } } } })).data.id;
  console.log(`listing ${locale}: ok`);
}

// --- Screenshots (6.9" iPhone set). Locales without their own folder fall back to the primary set in App Store Connect.
const md5 = async (b: Uint8Array) => Array.from(new Uint8Array(await stdCrypto.subtle.digest("MD5", b))).map((x) => x.toString(16).padStart(2, "0")).join("");
for (const locale of Object.keys(meta.localizations)) {
  const dir = new URL(`${locale}/`, root);
  let files: string[];
  try { files = [...Deno.readDirSync(dir)].map((e) => e.name).filter((n) => n.endsWith(".png")).sort(); } catch { continue; }
  const sets = (await api("GET", `/v1/appStoreVersionLocalizations/${locIds[locale]}/appScreenshotSets`)).data;
  let set = sets.find((s: any) => s.attributes.screenshotDisplayType === "APP_IPHONE_67");
  if (set) {
    for (const old of (await api("GET", `/v1/appScreenshotSets/${set.id}/appScreenshots`)).data) await api("DELETE", `/v1/appScreenshots/${old.id}`);
  } else {
    set = (await api("POST", "/v1/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: "APP_IPHONE_67" },
      relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: locIds[locale] } } } } })).data;
  }
  for (const name of files) {
    const bytes = await Deno.readFile(new URL(name, dir));
    const res = await api("POST", "/v1/appScreenshots", { data: { type: "appScreenshots", attributes: { fileName: name, fileSize: bytes.byteLength },
      relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set.id } } } } });
    for (const op of res.data.attributes.uploadOperations) {
      const headers: Record<string, string> = {};
      for (const h of op.requestHeaders ?? []) headers[h.name] = h.value;
      const r = await fetch(op.url, { method: op.method, headers, body: bytes.slice(op.offset, op.offset + op.length) });
      if (!r.ok) throw new Error(`upload ${name}: ${r.status}`);
    }
    await api("PATCH", `/v1/appScreenshots/${res.data.id}`, { data: { type: "appScreenshots", id: res.data.id,
      attributes: { uploaded: true, sourceFileChecksum: await md5(bytes) } } });
    console.log(`screenshot ${locale}/${name}: uploaded`);
  }
}
