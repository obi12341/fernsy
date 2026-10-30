import test from "node:test";
import assert from "node:assert/strict";
import { b64urlEncode, subscriptionStatus, notificationTransactionId } from "../apple.js";

const now = Date.parse("2026-10-30T12:00:00Z");
function jws(payload) { return `${b64urlEncode('{"alg":"ES256"}')}.${b64urlEncode(JSON.stringify(payload))}.sig`; }

async function appStoreEnv() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  return { APPSTORE_KEY: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----`, APPSTORE_KEY_ID: "KID", APPSTORE_ISSUER: "ISS" };
}

test("subscription status from Apple, sandbox fallback, refund, app account token", async () => {
  const env = await appStoreEnv();
  const calls = [];
  const fetchFn = async (url, init) => {
    calls.push(url);
    assert.match(init.headers.Authorization, /^Bearer .+\..+\..+$/);
    if (url.includes("storekit.itunes")) return new Response("", { status: 404 });
    return Response.json({ data: [{ lastTransactions: [{ originalTransactionId: "t1", status: 1,
      signedTransactionInfo: jws({ originalTransactionId: "t1", bundleId: "de.mobilistics.fernsy", productId: "p", expiresDate: now + 86400000, revocationDate: now - 1000, appAccountToken: "6F1C2B4A-0000-4000-8000-00000000ABCD" }) }] }] });
  };
  const s = await subscriptionStatus(env, "t1", fetchFn, now);
  assert.equal(calls.length, 2);
  assert.equal(s.productId, "p");
  assert.equal(s.revokedAt, new Date(now - 1000).toISOString());
  assert.equal(s.appAccountToken, "6f1c2b4a-0000-4000-8000-00000000abcd");
});

test("a purchase without an app account token reports null", async () => {
  const env = await appStoreEnv();
  const fetchFn = async () => Response.json({ data: [{ lastTransactions: [{ originalTransactionId: "t1",
    signedTransactionInfo: jws({ originalTransactionId: "t1", bundleId: "de.mobilistics.fernsy", productId: "p", expiresDate: now + 1 }) }] }] });
  assert.equal((await subscriptionStatus(env, "t1", fetchFn, now)).appAccountToken, null);
});

test("production 401 still asks the sandbox; a sandbox 401 fails", async () => {
  const env = await appStoreEnv();
  const sandbox = { status: 404 };
  const fetchFn = async (url) => url.includes("storekit.itunes") ? new Response("", { status: 401 }) : new Response("", sandbox);
  assert.equal(await subscriptionStatus(env, "t1", fetchFn, now), null);
  sandbox.status = 401;
  await assert.rejects(subscriptionStatus(env, "t1", fetchFn, now), /app store 401/);
});

test("notification names its transaction", () => {
  const payload = jws({ notificationType: "DID_RENEW", data: { signedTransactionInfo: jws({ originalTransactionId: "t9" }) } });
  assert.equal(notificationTransactionId(payload), "t9");
});
