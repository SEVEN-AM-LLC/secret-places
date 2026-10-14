// Submits the version in "Prepare for Submission" for App Review together with every
// in-app purchase (the first IAPs must ride along with a version).
// Run: deno run --allow-read --allow-env --allow-net submit_review.ts <buildNumber>
//
// NOTE (first release only): the public API refuses inAppPurchaseSubmissions until the app's
// first non-consumable has been approved (FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION),
// and reviewSubmissionItems has no IAP relationship. For 1.0.0 the IAPs were attached from the
// App Store Connect web session: POST /iris/v1/reviewSubmissionItems with relationship
// inAppPurchaseVersion -> the id from GET /iris/v2/inAppPurchases/{id}/versions.
// After the first approval, step 5 below works for new IAPs.
import { api } from "./asc.ts";
const APP = "6822694406";
const BUILD = Deno.args[0] ?? (() => { throw new Error("usage: submit_review.ts <buildNumber>"); })();

// 1) wait for the build to finish processing
let build: any;
for (let i = 0; i < 40; i++) {
  build = (await api("GET", `/v1/builds?filter[app]=${APP}&filter[version]=${BUILD}&filter[preReleaseVersion.version]=1.0.0`)).data[0];
  if (build?.attributes.processingState === "VALID") break;
  console.log(`build ${BUILD}: ${build?.attributes.processingState ?? "not visible yet"}…`);
  await new Promise((r) => setTimeout(r, 30000));
}
if (build?.attributes.processingState !== "VALID") throw new Error("build not processed in time");

// 2) attach it, 3) content rights (OSM data under ODbL, Google Places photos under its API terms; no event posters)
const v = (await api("GET", `/v1/apps/${APP}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION`)).data[0];
await api("PATCH", `/v1/appStoreVersions/${v.id}/relationships/build`, { data: { type: "builds", id: build.id } });
await api("PATCH", `/v1/apps/${APP}`, { data: { type: "apps", id: APP, attributes: { contentRightsDeclaration: "USES_THIRD_PARTY_CONTENT" } } });
console.log(`version ${v.attributes.versionString} <- build ${BUILD}; content rights declared`);

// 4) review submission with the version
const open = (await api("GET", `/v1/reviewSubmissions?filter[app]=${APP}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW`)).data;
const sub = open[0] ?? (await api("POST", "/v1/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform: "IOS" },
  relationships: { app: { data: { type: "apps", id: APP } } } } })).data;
const items = (await api("GET", `/v1/reviewSubmissions/${sub.id}/items`)).data;
if (!items.length) {
  await api("POST", "/v1/reviewSubmissionItems", { data: { type: "reviewSubmissionItems",
    relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub.id } }, appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } });
}
console.log("review submission", sub.id, "has the version");

// 5) every IAP rides along
const iaps = (await api("GET", `/v1/apps/${APP}/inAppPurchasesV2?limit=200&fields[inAppPurchases]=productId,state`)).data;
let ok = 0; const fails: string[] = [];
for (const i of iaps) {
  if (i.attributes.state !== "READY_TO_SUBMIT") { fails.push(`${i.attributes.productId}: ${i.attributes.state}`); continue; }
  try { await api("POST", "/v1/inAppPurchaseSubmissions", { data: { type: "inAppPurchaseSubmissions",
    relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: i.id } } } } }); ok++; }
  catch (e) { const m = String(e); fails.push(`${i.attributes.productId}: ${m.slice(m.indexOf('"code"'), m.indexOf('"code"') + 200)}`); }
}
console.log(`IAPs added: ${ok}/${iaps.length}`);
for (const f of fails.slice(0, 5)) console.log("  FAIL", f);
if (ok !== iaps.length) { console.log("NOT SUBMITTED — fix the IAPs above first"); Deno.exit(1); }

// 6) submit
const done = await api("PATCH", `/v1/reviewSubmissions/${sub.id}`, { data: { type: "reviewSubmissions", id: sub.id, attributes: { submitted: true } } });
console.log("SUBMITTED:", done.data.attributes.state, done.data.attributes.submittedDate ?? "");
