import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { makeDB, makeStorage } from "./d1.js";
import { handle } from "../worker.js";
import { b64urlEncode } from "../apple.js";
import * as paddle from "../paddle.js";

const DAY = 86400000;
const SECRET = "pdl_ntfset_test_secret";

function sign(body, ts) { return `ts=${ts};h1=${createHmac("sha256", SECRET).update(`${ts}:${body}`).digest("hex")}`; }

function deviceKey() {
  const accountId = crypto.randomUUID();
  return { accountId, auth: `Key ${accountId}:${b64urlEncode(crypto.getRandomValues(new Uint8Array(32)))}` };
}

function setup({ apiKey = true } = {}) {
  let now = Date.parse("2026-11-01T12:00:00Z");
  const storage = makeStorage();
  const env = { DB: makeDB(), BUCKET: storage.bucket, ACCOUNT_ID: "acc", BUCKET_NAME: "b", S3_KEY: "k", S3_SECRET: "s",
    PADDLE_ENV: "sandbox", PADDLE_WEBHOOK_SECRET: SECRET, CHECKOUT_SECRET: "checkout-secret", PADDLE_PRICE_ID: "pri_test",
    PADDLE_CLIENT_TOKEN: "test_client", ...(apiKey ? { PADDLE_API_KEY: "pdl_sdbx_key" } : {}), CHECKOUT_ORIGINS: "http://localhost:8000" };
  // Paddle's API (sandbox): subscriptions by id, portal sessions, price previews.
  const paddleAPI = { subscriptions: new Map(), calls: [] };
  const fetchFn = async (url, init = {}) => {
    const u = new URL(String(url));
    if (u.host === "sandbox-api.paddle.com") {
      paddleAPI.calls.push(`${init.method} ${u.pathname}`);
      if (u.pathname.startsWith("/subscriptions/")) {
        const sub = paddleAPI.subscriptions.get(u.pathname.split("/").pop());
        return sub ? Response.json({ data: sub }) : new Response("", { status: 404 });
      }
      if (u.pathname.endsWith("/portal-sessions")) {
        return Response.json({ data: { urls: { general: { overview: "https://sandbox-customer-portal.paddle.com/cpl_x?token=t" } } } });
      }
      if (u.pathname === "/pricing-preview") {
        return Response.json({ data: { currency_code: "EUR", details: { line_items: [{ formatted_totals: { total: "€2.99" } }] } } });
      }
    }
    return storage.fetch(url, init);
  };
  const deps = { fetch: fetchFn, now: () => now };
  const call = async (method, path, { body, auth, headers = {}, raw } = {}) => {
    const h = { ...headers };
    if (auth) h.Authorization = auth;
    const res = await handle(new Request("https://cloud.test" + path, {
      method, headers: h, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
    }), env, deps);
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  };
  const notify = (event) => {
    const raw = JSON.stringify(event);
    return call("POST", "/v1/paddle/notifications", { raw, headers: { "Paddle-Signature": sign(raw, Math.floor(now / 1000)) } });
  };
  return { env, deps, call, notify, paddleAPI, advance: (ms) => { now += ms; }, now: () => now };
}

function subscriptionEvent(type, { token, status = "active", ends, occurred, canceledAt, id = "sub_01test" }) {
  return {
    event_id: `evt_${Math.random().toString(36).slice(2)}`, event_type: type, occurred_at: occurred,
    data: { id, status, customer_id: "ctm_01test", custom_data: token ? { fernsy_checkout: token } : null,
      current_billing_period: ends ? { starts_at: occurred, ends_at: ends } : null, next_billed_at: ends ?? null,
      canceled_at: canceledAt ?? null, items: [{ price: { id: "pri_test" } }] },
  };
}

test("signature: valid, forged, too old, rotated secrets", async () => {
  const now = Date.parse("2026-11-01T12:00:00Z"), ts = Math.floor(now / 1000);
  const body = '{"a":1}';
  assert.ok(await paddle.verifySignature(sign(body, ts), body, SECRET, now));
  assert.ok(!(await paddle.verifySignature(sign(body, ts), '{"a":2}', SECRET, now)));
  assert.ok(!(await paddle.verifySignature(sign(body, ts - 600), body, SECRET, now)));
  assert.ok(!(await paddle.verifySignature(`ts=${ts};h1=deadbeef`, body, SECRET, now)));
  assert.ok(await paddle.verifySignature(`ts=${ts};h1=deadbeef;${sign(body, ts).split(";")[1]}`, body, SECRET, now));
  assert.ok(!(await paddle.verifySignature(null, body, SECRET, now)));
});

test("checkout token: round trip, forged, expired, other environment", async () => {
  const env = { CHECKOUT_SECRET: "s", PADDLE_ENV: "sandbox" };
  const now = Date.parse("2026-11-01T12:00:00Z");
  const token = await paddle.makeCheckoutToken(env, "acc-1", now);
  assert.equal(await paddle.readCheckoutToken(env, token, now), "acc-1");
  assert.equal(await paddle.readCheckoutToken(env, token.replace(/.$/, "0"), now), null);
  assert.equal(await paddle.readCheckoutToken(env, token, now + 2 * 3600 * 1000), null);
  assert.equal(await paddle.readCheckoutToken(env, token, now + 2 * 3600 * 1000, { ignoreExpiry: true }), "acc-1");
  assert.equal(await paddle.readCheckoutToken({ ...env, PADDLE_ENV: "live" }, token, now), null);
});

test("checkout: token for an account without a subscription, verify from the page with CORS", async () => {
  const t = setup();
  const key = deviceKey();
  const start = await t.call("POST", "/v1/checkout", { auth: key.auth, headers: { "CF-IPCountry": "DE" } });
  assert.equal(start.status, 200);
  assert.deepEqual(start.body.price, { amount: "€2.99", currency: "EUR" });
  const verify = await t.call("POST", "/v1/checkout/verify", { body: { token: start.body.token }, headers: { Origin: "https://www.fernsy.app" } });
  assert.equal(verify.status, 200);
  assert.deepEqual(verify.body, { environment: "sandbox", clientToken: "test_client", priceId: "pri_test", alreadySubscribed: false });
  assert.equal(verify.headers.get("Access-Control-Allow-Origin"), "https://www.fernsy.app");
  const other = await t.call("POST", "/v1/checkout/verify", { body: { token: start.body.token }, headers: { Origin: "https://evil.example" } });
  assert.equal(other.headers.get("Access-Control-Allow-Origin"), null);
  assert.equal((await t.call("POST", "/v1/checkout/verify", { body: { token: "x.y" } })).body.error, "bad_token");
  assert.equal((await t.call("OPTIONS", "/v1/checkout/verify", { headers: { Origin: "http://localhost:8000" } })).status, 204);
});

test("webhooks: created makes the account active, renewal extends, cancel ends with grace", async () => {
  const t = setup();
  const key = deviceKey();
  const { token } = (await t.call("POST", "/v1/checkout", { auth: key.auth })).body;
  const start = new Date(t.now()).toISOString(), periodEnd = new Date(t.now() + 30 * DAY).toISOString();
  assert.equal((await t.notify(subscriptionEvent("subscription.created", { token, ends: periodEnd, occurred: start }))).status, 200);
  let account = (await t.call("GET", "/v1/account", { auth: key.auth })).body;
  assert.equal(account.state, "active");
  assert.equal(account.provider, "paddle");
  assert.equal(account.expiresAt, periodEnd);
  // A second purchase is refused, by the app's route and on the page.
  assert.equal((await t.call("POST", "/v1/checkout", { auth: key.auth })).body.error, "already_subscribed");
  assert.equal((await t.call("POST", "/v1/checkout/verify", { body: { token } })).body.alreadySubscribed, true);

  t.advance(30 * DAY);
  const renewed = new Date(t.now() + 30 * DAY).toISOString();
  await t.notify(subscriptionEvent("subscription.updated", { token, ends: renewed, occurred: new Date(t.now()).toISOString() }));
  // An older event that arrives late changes nothing.
  await t.notify(subscriptionEvent("subscription.updated", { token, ends: periodEnd, occurred: start }));
  assert.equal((await t.call("GET", "/v1/account", { auth: key.auth })).body.expiresAt, renewed);

  t.advance(10 * DAY);
  const canceledAt = new Date(t.now()).toISOString();
  await t.notify(subscriptionEvent("subscription.canceled", { token, status: "canceled", canceledAt, occurred: canceledAt }));
  account = (await t.call("GET", "/v1/account", { auth: key.auth })).body;
  assert.equal(account.state, "grace");
  assert.equal(account.endedAt, canceledAt);
});

test("webhooks: forged, foreign and unrelated events change nothing", async () => {
  const t = setup();
  const key = deviceKey();
  const { token } = (await t.call("POST", "/v1/checkout", { auth: key.auth })).body;
  const event = subscriptionEvent("subscription.created", { token, ends: new Date(t.now() + 30 * DAY).toISOString(), occurred: new Date(t.now()).toISOString() });
  const raw = JSON.stringify(event);
  assert.equal((await t.call("POST", "/v1/paddle/notifications", { raw, headers: { "Paddle-Signature": `ts=${Math.floor(t.now() / 1000)};h1=00` } })).status, 401);
  assert.equal((await t.notify({ ...event, data: { ...event.data, custom_data: null } })).status, 200);
  assert.equal((await t.notify({ ...event, data: { ...event.data, custom_data: { fernsy_checkout: "forged.token" } } })).status, 200);
  assert.equal((await t.notify({ event_type: "transaction.completed", data: { id: "txn_1" } })).status, 200);
  assert.equal((await t.call("GET", "/v1/account", { auth: key.auth })).body.state, "none");
});

test("portal link for a Paddle subscriber; refresh from Paddle when the stored period ended", async () => {
  const t = setup();
  const key = deviceKey();
  assert.equal((await t.call("POST", "/v1/subscription/portal", { auth: key.auth })).body.error, "not_paddle");
  const { token } = (await t.call("POST", "/v1/checkout", { auth: key.auth })).body;
  const periodEnd = new Date(t.now() + 30 * DAY).toISOString();
  await t.notify(subscriptionEvent("subscription.created", { token, ends: periodEnd, occurred: new Date(t.now()).toISOString() }));
  const portal = await t.call("POST", "/v1/subscription/portal", { auth: key.auth });
  assert.equal(portal.status, 200);
  assert.match(portal.body.url, /customer-portal\.paddle\.com/);
  assert.ok(t.paddleAPI.calls.includes("POST /customers/ctm_01test/portal-sessions"));

  // The renewal webhook got lost: the account asks Paddle once the stored period is over.
  t.advance(31 * DAY);
  t.paddleAPI.subscriptions.set("sub_01test", subscriptionEvent("x", { token, ends: new Date(t.now() + 29 * DAY).toISOString(), occurred: "" }).data);
  const account = (await t.call("GET", "/v1/account", { auth: key.auth })).body;
  assert.equal(account.state, "active");
  assert.ok(t.paddleAPI.calls.includes("GET /subscriptions/sub_01test"));
});

test("without Paddle settings the routes say so", async () => {
  const t = setup();
  delete t.env.PADDLE_WEBHOOK_SECRET;
  const key = deviceKey();
  assert.equal((await t.call("POST", "/v1/checkout", { auth: key.auth })).body.error, "paddle_not_configured");
  assert.equal((await t.call("POST", "/v1/paddle/notifications", { raw: "{}" })).status, 503);
});
