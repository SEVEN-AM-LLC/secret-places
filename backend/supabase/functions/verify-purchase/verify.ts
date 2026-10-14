// StoreKit 2 transaction verification for verify-purchase.
//
// One deployment serves BOTH App Store environments:
//   • Production — real customers.
//   • Sandbox    — TestFlight testers and App Review (reviewers buy in Sandbox
//                  against the production build, so it must keep working).
// The environment is read from the (still unverified) payload only to pick the
// matching verifier; Apple's library then checks the x5c chain against Apple's
// root CA, the signature, the bundle id AND that the environment matches, so a
// forged "environment" field can't get past it.
import { Buffer } from "node:buffer";

export type AppleEnvironment = "Production" | "Sandbox";

export interface VerifyConfig {
  strict: boolean;           // false only for local testing (APPLE_VERIFY=dev)
  bundleId: string;
  appAppleId?: number;       // App Store Connect "Apple ID" (required for Production)
  allowSandbox: boolean;
  rootCerts: Uint8Array[];
}

export function configFromEnv(get: (k: string) => string | undefined): VerifyConfig {
  const appId = get("APPLE_APP_ID");
  return {
    strict: (get("APPLE_VERIFY") ?? "strict") !== "dev",
    bundleId: get("APPLE_BUNDLE_ID") ?? "com.secretplaces.app",
    appAppleId: appId ? Number(appId) : undefined,
    allowSandbox: (get("APPLE_ALLOW_SANDBOX") ?? "true") !== "false",
    rootCerts: (get("APPLE_ROOT_CERTS") ?? "").split(",").map((s) => s.trim()).filter(Boolean)
      .map((b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))),
  };
}

export class VerifyError extends Error {
  constructor(public code: string) { super(code); }
}

function b64urlToJson(seg: string): any {
  const b64 = seg.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(seg.length / 4) * 4, "=");
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
}

/** Decodes the JWS payload WITHOUT verifying it. Never trust the result on its own. */
export function decodeUnverified(jws: string): any {
  const parts = jws.split(".");
  if (parts.length !== 3 || !parts[1]) throw new VerifyError("malformed_jws");
  try { return b64urlToJson(parts[1]); } catch { throw new VerifyError("malformed_jws"); }
}

/** Which verifier to use for this transaction, or a rejection code. */
export function selectEnvironment(claimed: unknown, cfg: VerifyConfig): AppleEnvironment {
  if (claimed === "Production") {
    if (cfg.appAppleId === undefined || Number.isNaN(cfg.appAppleId)) throw new VerifyError("apple_app_id_missing");
    return "Production";
  }
  if (claimed === "Sandbox") {
    if (!cfg.allowSandbox) throw new VerifyError("sandbox_not_allowed");
    return "Sandbox";
  }
  // "Xcode" / "LocalTesting" transactions are signed by a local Xcode cert, not Apple.
  throw new VerifyError("unsupported_environment");
}

type Verifier = { verifyAndDecodeTransaction(jws: string): Promise<any> };
const verifiers = new Map<AppleEnvironment, Verifier>();

async function verifierFor(env: AppleEnvironment, cfg: VerifyConfig): Promise<Verifier> {
  const cached = verifiers.get(env);
  if (cached) return cached;
  if (cfg.rootCerts.length === 0) throw new VerifyError("apple_root_certs_missing");
  const lib = await import("npm:@apple/app-store-server-library@1.4.0");
  const v = new lib.SignedDataVerifier(
    cfg.rootCerts.map((c) => Buffer.from(c)),
    true,   // online OCSP revocation checks of the signing chain
    env === "Production" ? lib.Environment.PRODUCTION : lib.Environment.SANDBOX,
    cfg.bundleId,
    env === "Production" ? cfg.appAppleId : undefined,
  );
  verifiers.set(env, v);
  return v;
}

/** Verifies a signed transaction and returns its decoded payload. */
export async function verifyTransaction(jws: string, cfg: VerifyConfig): Promise<any> {
  const claimed = decodeUnverified(jws);
  if (!cfg.strict) return claimed;   // local testing only — trusts the client!
  const env = selectEnvironment(claimed.environment, cfg);
  try {
    return await (await verifierFor(env, cfg)).verifyAndDecodeTransaction(jws);
  } catch (e) {
    if (e instanceof VerifyError) throw e;
    // VerificationStatus.RETRYABLE_VERIFICATION_FAILURE: Apple's OCSP responder was unreachable.
    if ((e as { status?: number })?.status === 2) throw new VerifyError("verification_unavailable");
    throw new VerifyError("signature_invalid");
  }
}
