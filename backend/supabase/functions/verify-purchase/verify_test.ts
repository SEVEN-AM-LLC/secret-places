// deno test --allow-read --allow-env --allow-net verify_test.ts
import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { configFromEnv, decodeUnverified, selectEnvironment, verifyTransaction, VerifyError } from "./verify.ts";

const b64url = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const fakeJws = (payload: unknown, header: unknown = { alg: "ES256", x5c: ["AAAA", "AAAA", "AAAA"] }) =>
  `${b64url(header)}.${b64url(payload)}.c2lnbmF0dXJl`;

// Any well-formed root works for negative tests: a forged JWS can never chain to it.
const SELF_SIGNED_ROOT = Deno.readTextFileSync(new URL("./testdata/root.b64", import.meta.url)).trim();
const env = (o: Record<string, string>) => (k: string) => o[k];
const strictCfg = (extra: Record<string, string> = {}) =>
  configFromEnv(env({ APPLE_APP_ID: "1234567890", APPLE_ROOT_CERTS: SELF_SIGNED_ROOT, ...extra }));

Deno.test("strict verification is the default", () => {
  assertEquals(configFromEnv(env({})).strict, true);
  assertEquals(configFromEnv(env({ APPLE_VERIFY: "dev" })).strict, false);
  assertEquals(configFromEnv(env({})).allowSandbox, true);
});

Deno.test("both App Store environments are accepted", () => {
  const cfg = strictCfg();
  assertEquals(selectEnvironment("Production", cfg), "Production");
  assertEquals(selectEnvironment("Sandbox", cfg), "Sandbox");
});

Deno.test("Xcode / unknown environments are rejected", () => {
  for (const e of ["Xcode", "LocalTesting", undefined, "production"]) {
    const err = assertThrows(() => selectEnvironment(e, strictCfg()), VerifyError);
    assertEquals(err.code, "unsupported_environment");
  }
});

Deno.test("Sandbox can be switched off", () => {
  const err = assertThrows(() => selectEnvironment("Sandbox", strictCfg({ APPLE_ALLOW_SANDBOX: "false" })), VerifyError);
  assertEquals(err.code, "sandbox_not_allowed");
});

Deno.test("Production needs the App Apple ID", () => {
  const cfg = configFromEnv(env({ APPLE_ROOT_CERTS: SELF_SIGNED_ROOT }));
  const err = assertThrows(() => selectEnvironment("Production", cfg), VerifyError);
  assertEquals(err.code, "apple_app_id_missing");
});

Deno.test("malformed JWS is rejected", () => {
  for (const j of ["", "abc", "a.b", "a.!!!.c"]) assertThrows(() => decodeUnverified(j), VerifyError);
});

Deno.test("missing root certs is a configuration error", async () => {
  const cfg = configFromEnv(env({ APPLE_APP_ID: "1" }));
  const err = await assertRejects(() => verifyTransaction(fakeJws({ environment: "Sandbox" }), cfg), VerifyError);
  assertEquals(err.code, "apple_root_certs_missing");
});

for (const environment of ["Production", "Sandbox"]) {
  Deno.test(`forged ${environment} transaction fails signature verification`, async () => {
    const forged = fakeJws({ environment, bundleId: "com.secretplaces.app", productId: "com.secretplaces.place.x", transactionId: "1" });
    const err = await assertRejects(() => verifyTransaction(forged, strictCfg()), VerifyError);
    assertEquals(err.code, "signature_invalid");
  });
}

Deno.test("dev mode decodes without verifying (local only)", async () => {
  const tx = await verifyTransaction(fakeJws({ environment: "Xcode", productId: "p" }), configFromEnv(env({ APPLE_VERIFY: "dev" })));
  assertEquals(tx.productId, "p");
});
