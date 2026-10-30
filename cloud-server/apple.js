// Apple for Fernsy Cloud (cloud-server design F; cloud-account-from-icloud-key design C): the
// App Store Server API as the only source of truth for subscriptions. WebCrypto only.

const enc = new TextEncoder();
const dec = new TextDecoder();

export class AppleNotConfigured extends Error {}

export function b64urlEncode(bytes) {
  const b = typeof bytes === "string" ? enc.encode(bytes) : new Uint8Array(bytes);
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(s) {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/// The parts of a JWT/JWS without checking anything.
export function decodeJWT(token) {
  const parts = String(token).split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  return {
    header: JSON.parse(dec.decode(b64urlDecode(parts[0]))),
    payload: JSON.parse(dec.decode(b64urlDecode(parts[1]))),
    signed: enc.encode(parts[0] + "." + parts[1]),
    signature: b64urlDecode(parts[2]),
  };
}

// MARK: App Store Server API

const PRODUCTION = "https://api.storekit.itunes.apple.com";
const SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

export function appStoreConfigured(env) {
  return Boolean(env.APPSTORE_KEY && env.APPSTORE_KEY_ID && env.APPSTORE_ISSUER);
}

function pemToBytes(pem) {
  return b64urlDecode(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "").replace(/\+/g, "-").replace(/\//g, "_"));
}

/// The ES256 token for the App Store Server API.
export async function appStoreToken(env, bundleId, now = Date.now()) {
  if (!appStoreConfigured(env)) throw new AppleNotConfigured();
  const key = await crypto.subtle.importKey("pkcs8", pemToBytes(env.APPSTORE_KEY), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64urlEncode(JSON.stringify({ alg: "ES256", kid: env.APPSTORE_KEY_ID, typ: "JWT" }));
  const iat = Math.floor(now / 1000);
  const body = b64urlEncode(JSON.stringify({ iss: env.APPSTORE_ISSUER, iat, exp: iat + 1200, aud: "appstoreconnect-v1", bid: bundleId }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(head + "." + body));
  return `${head}.${body}.${b64urlEncode(sig)}`;
}

/// The subscription behind an original transaction id, as Apple's server reports it:
/// {originalTransactionId, bundleId, productId, expiresAt, revokedAt, appAccountToken} or null
/// when Apple does
/// not know it. Production first, then the sandbox (as Apple recommends for TestFlight and
/// StoreKit sandbox purchases). Nothing from the app is trusted: this answer comes over TLS
/// from Apple, so its signed fields are read without checking the certificate chain.
/// Production answers 401 while the app has no approved in-app purchase yet; the sandbox is
/// asked then too.
export async function subscriptionStatus(env, originalTransactionId, fetchFn = fetch, now = Date.now()) {
  const bundleId = (env.BUNDLE_IDS || "de.mobilistics.fernsy").split(",")[0].trim();
  const token = await appStoreToken(env, bundleId, now);
  for (const base of [PRODUCTION, SANDBOX]) {
    const res = await fetchFn(`${base}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`,
      { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 404 || (res.status === 401 && base === PRODUCTION)) continue;
    if (!res.ok) throw new Error(`app store ${res.status}`);
    const body = await res.json();
    let latest = null;
    for (const group of body.data || []) {
      for (const t of group.lastTransactions || []) {
        if (t.originalTransactionId !== originalTransactionId || !t.signedTransactionInfo) continue;
        const info = decodeJWT(t.signedTransactionInfo).payload;
        if (!latest || (info.expiresDate || 0) > (latest.expiresDate || 0)) latest = info;
      }
    }
    if (!latest) return null;
    return {
      originalTransactionId,
      bundleId: latest.bundleId,
      productId: latest.productId,
      expiresAt: latest.expiresDate ? new Date(latest.expiresDate).toISOString() : null,
      revokedAt: latest.revocationDate ? new Date(latest.revocationDate).toISOString() : null,
      // The account the purchase was made for (StoreKit's appAccountToken), lowercased.
      appAccountToken: latest.appAccountToken ? String(latest.appAccountToken).toLowerCase() : null,
    };
  }
  return null;
}

/// The original transaction id named in an App Store Server Notification V2. Only used to
/// know whom to ask Apple about; nothing else in the payload is trusted.
export function notificationTransactionId(signedPayload) {
  const payload = decodeJWT(signedPayload).payload;
  const info = payload?.data?.signedTransactionInfo;
  return info ? decodeJWT(info).payload.originalTransactionId || null : null;
}
