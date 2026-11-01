import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { makeDB, makeStorage } from "./d1.js";
import { handle } from "../worker.js";
import { b64urlEncode } from "../apple.js";
import * as stripe from "../stripe.js";

const DAY = 86400000;
const SECRET = "whsec_test_secret";

function sign(body, ts) { return `t=${ts},v1=${createHmac("sha256", SECRET).update(`${ts}.${body}`).digest("hex")}`; }

function deviceKey() {
  const accountId = crypto.randomUUID();
  return { accountId, auth: `Key ${accountId}:${b64urlEncode(crypto.getRandomValues(new Uint8Array(32)))}` };
}

/// A small stand-in for Stripe's API: customers, subscriptions, portal sessions and the price.
function fakeStripe(now) {
  const state = { customers: new Map(), subscriptions: new Map(), calls: [], next: 1 };
  const form = (text) => Object.fromEntries(new URLSearchParams(text ?? ""));
  const sec = () => Math.floor(now() / 1000);
  const fetchFn = async (url, init = {}) => {
    const u = new URL(String(url));
    const method = init.method ?? "GET";
    const p = u.pathname;
    state.calls.push(`${method} ${p}`);
    assert.equal(init.headers?.["Stripe-Version"], stripe.API_VERSION);
    const b = form(init.body);
    if (method === "POST" && p === "/v1/customers") {
      if (b["address[country]"] === "XX") return Response.json({ error: { code: "customer_tax_location_invalid", message: "tax location invalid" } }, { status: 400 });
      const c = { id: `cus_${state.next++}`, email: b.email, metadata: { fernsy_account: b["metadata[fernsy_account]"] } };
      state.customers.set(c.id, c);
      return Response.json(c);
    }
    if (method === "GET" && p === "/v1/customers") {
      return Response.json({ data: [...state.customers.values()].filter((c) => c.email === u.searchParams.get("email")) });
    }
    if (method === "POST" && p === "/v1/subscriptions") {
      state.lastCreate = b;
      const s = { id: `sub_${state.next++}`, status: "incomplete", customer: b.customer, cancel_at_period_end: false,
        metadata: { fernsy_account: b["metadata[fernsy_account]"] },
        items: { data: [{ price: { id: b["items[0][price]"] }, current_period_end: sec() + 30 * 86400 }] },
        latest_invoice: { confirmation_secret: { client_secret: "pi_secret_1" } } };
      state.subscriptions.set(s.id, s);
      return Response.json(s);
    }
    if (method === "GET" && p === "/v1/subscriptions") {
      return Response.json({ data: [...state.subscriptions.values()].filter((s) => s.customer === u.searchParams.get("customer")) });
    }
    const subMatch = p.match(/^\/v1\/subscriptions\/(sub_\w+)$/);
    if (subMatch) {
      const s = state.subscriptions.get(subMatch[1]);
      if (!s) return Response.json({ error: { code: "resource_missing" } }, { status: 404 });
      if (method === "POST" && b.cancel_at_period_end === "true") s.cancel_at_period_end = true;
      return Response.json(s);
    }
    if (method === "POST" && p === "/v1/billing_portal/sessions") { state.lastPortal = b; return Response.json({ url: "https://billing.stripe.com/p/session/test_x" }); }
    if (method === "GET" && p.startsWith("/v1/prices/")) return Response.json({ id: "price_test", unit_amount: 349, currency: "eur" });
    return Response.json({ error: { code: "not_faked" } }, { status: 500 });
  };
  return { state, fetchFn };
}

function setup({ configured = true } = {}) {
  let now = Date.parse("2026-11-02T12:00:00Z");
  const storage = makeStorage();
  const env = { DB: makeDB(), BUCKET: storage.bucket, ACCOUNT_ID: "acc", BUCKET_NAME: "b", S3_KEY: "k", S3_SECRET: "s",
    STRIPE_ENV: "test", CHECKOUT_SECRET: "checkout-secret", CHECKOUT_ORIGINS: "http://localhost:8000",
    ...(configured ? { STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: SECRET, STRIPE_PUBLISHABLE_KEY: "pk_test_x", STRIPE_PRICE_ID: "price_test" } : {}) };
  const fake = fakeStripe(() => now);
  const deps = { fetch: (url, init) => (String(url).startsWith("https://api.stripe.com") ? fake.fetchFn(url, init) : storage.fetch(url, init)), now: () => now };
  const call = async (method, path, { body, auth, headers = {}, raw } = {}) => {
    const h = { ...headers };
    if (auth) h.Authorization = auth;
    const res = await handle(new Request("https://cloud.test" + path, {
      method, headers: h, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
    }), env, deps);
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  };
  const notify = (type, object, created = Math.floor(now / 1000)) => {
    const raw = JSON.stringify({ id: `evt_${created}`, type, created, data: { object } });
    return call("POST", "/v1/stripe/notifications", { raw, headers: { "Stripe-Signature": sign(raw, Math.floor(now / 1000)) } });
  };
  return { env, call, notify, stripe: fake.state, advance: (ms) => { now += ms; }, now: () => now };
}

async function buy(t, key, overrides = {}) {
  const { token } = (await t.call("POST", "/v1/checkout", { auth: key.auth })).body;
  const order = await t.call("POST", "/v1/checkout/subscribe", { headers: { Origin: "https://www.fernsy.app" },
    body: { token, email: "buyer@example.com", country: "DE", postalCode: "10115", consent: true, ...overrides } });
  return { token, order };
}

test("signature: valid, forged, too old, several v1", async () => {
  const now = Date.parse("2026-11-02T12:00:00Z"), ts = Math.floor(now / 1000);
  const body = '{"a":1}';
  assert.ok(await stripe.verifySignature(sign(body, ts), body, SECRET, now));
  assert.ok(!(await stripe.verifySignature(sign(body, ts), '{"a":2}', SECRET, now)));
  assert.ok(!(await stripe.verifySignature(sign(body, ts - 600), body, SECRET, now)));
  assert.ok(await stripe.verifySignature(`t=${ts},v1=deadbeef,${sign(body, ts).split(",")[1]}`, body, SECRET, now));
  assert.ok(!(await stripe.verifySignature(null, body, SECRET, now)));
});

test("checkout token: round trip, forged, expired, other environment", async () => {
  const env = { CHECKOUT_SECRET: "s", STRIPE_ENV: "test" };
  const now = Date.parse("2026-11-02T12:00:00Z");
  const token = await stripe.makeCheckoutToken(env, "acc-1", now);
  assert.equal(await stripe.readCheckoutToken(env, token, now), "acc-1");
  assert.equal(await stripe.readCheckoutToken(env, token.replace(/.$/, "0"), now), null);
  assert.equal(await stripe.readCheckoutToken(env, token, now + 2 * 3600 * 1000), null);
  assert.equal(await stripe.readCheckoutToken({ ...env, STRIPE_ENV: "live" }, token, now), null);
});

test("form encoding of nested parameters", () => {
  assert.deepEqual(stripe.formEncode({ items: [{ price: "p" }], billing_mode: { type: "flexible" }, expand: ["a.b"] }),
    ["items%5B0%5D%5Bprice%5D=p", "billing_mode%5Btype%5D=flexible", "expand%5B0%5D=a.b"]);
});

test("checkout: verify with CORS, subscribe creates the subscription for the token's account", async () => {
  const t = setup();
  const key = deviceKey();
  const start = await t.call("POST", "/v1/checkout", { auth: key.auth });
  assert.equal(start.status, 200);
  assert.deepEqual(start.body.price, { amount: "€3.49", currency: "EUR" });
  const verify = await t.call("POST", "/v1/checkout/verify", { body: { token: start.body.token }, headers: { Origin: "https://www.fernsy.app" } });
  assert.equal(verify.status, 200);
  assert.equal(verify.body.publishableKey, "pk_test_x");
  assert.equal(verify.body.alreadySubscribed, false);
  assert.equal(verify.headers.get("Access-Control-Allow-Origin"), "https://www.fernsy.app");
  const other = await t.call("POST", "/v1/checkout/verify", { body: { token: start.body.token }, headers: { Origin: "https://evil.example" } });
  assert.equal(other.headers.get("Access-Control-Allow-Origin"), null);
  assert.equal((await t.call("POST", "/v1/checkout/verify", { body: { token: "x.y" } })).body.error, "bad_token");
  assert.equal((await t.call("OPTIONS", "/v1/checkout/subscribe", { headers: { Origin: "http://localhost:8000" } })).status, 204);

  const { order } = await buy(t, key);
  assert.equal(order.status, 200);
  assert.equal(order.body.clientSecret, "pi_secret_1");
  const created = t.stripe.lastCreate;
  assert.equal(created["metadata[fernsy_account]"], key.accountId);
  assert.equal(created.payment_behavior, "default_incomplete");
  assert.equal(created["billing_mode[type]"], "flexible");
  assert.equal(created["automatic_tax[enabled]"], "true");
  assert.equal(created["expand[0]"], "latest_invoice.confirmation_secret");
  assert.ok(created["metadata[start_consent_at]"]);
});

test("subscribe refuses without consent, with a bad address and for subscribed accounts", async () => {
  const t = setup();
  const key = deviceKey();
  assert.equal((await buy(t, key, { consent: false })).order.body.error, "no_consent");
  assert.equal((await buy(t, key, { email: "nope" })).order.body.error, "bad_email");
  assert.equal((await buy(t, key, { country: "XX" })).order.body.error, "bad_address");
});

test("webhooks: active links the account, cancel at period end keeps it until then, deleted ends it", async () => {
  const t = setup();
  const key = deviceKey();
  await buy(t, key);
  const sub = [...t.stripe.subscriptions.values()][0];
  // Not paid yet: nothing changes.
  await t.notify("customer.subscription.created", sub);
  assert.equal((await t.call("GET", "/v1/account", { auth: key.auth })).body.state, "none");

  sub.status = "active";
  assert.equal((await t.notify("customer.subscription.updated", sub)).status, 200);
  let account = (await t.call("GET", "/v1/account", { auth: key.auth })).body;
  assert.equal(account.state, "active");
  assert.equal(account.provider, "stripe");
  const periodEnd = new Date(sub.items.data[0].current_period_end * 1000).toISOString();
  assert.equal(account.expiresAt, periodEnd);
  // A second purchase is refused, by the app's route and on the page.
  assert.equal((await t.call("POST", "/v1/checkout", { auth: key.auth })).body.error, "already_subscribed");

  sub.cancel_at_period_end = true;
  t.advance(1000);
  await t.notify("customer.subscription.updated", sub);
  // An older event that arrives late changes nothing.
  await t.notify("customer.subscription.updated", { ...sub, status: "canceled", ended_at: Math.floor(t.now() / 1000) - 10 }, Math.floor(t.now() / 1000) - 60);
  assert.equal((await t.call("GET", "/v1/account", { auth: key.auth })).body.state, "active");

  t.advance(30 * DAY);
  const ended = Math.floor(t.now() / 1000);
  Object.assign(sub, { status: "canceled", ended_at: ended });
  await t.notify("customer.subscription.deleted", sub);
  account = (await t.call("GET", "/v1/account", { auth: key.auth })).body;
  assert.equal(account.state, "grace");
  assert.equal(account.endedAt, new Date(ended * 1000).toISOString());
});

test("webhooks: forged signatures and foreign subscriptions change nothing", async () => {
  const t = setup();
  const key = deviceKey();
  await buy(t, key);
  const sub = { ...[...t.stripe.subscriptions.values()][0], status: "active" };
  const raw = JSON.stringify({ type: "customer.subscription.updated", created: 1, data: { object: sub } });
  assert.equal((await t.call("POST", "/v1/stripe/notifications", { raw, headers: { "Stripe-Signature": `t=${Math.floor(t.now() / 1000)},v1=00` } })).status, 400);
  assert.equal((await t.notify("customer.subscription.updated", { ...sub, metadata: {} })).status, 200);
  assert.equal((await t.notify("customer.subscription.updated", { ...sub, metadata: { fernsy_account: crypto.randomUUID() } })).status, 200);
  assert.equal((await t.notify("invoice.paid", { id: "in_1" })).status, 200);
  assert.equal((await t.call("GET", "/v1/account", { auth: key.auth })).body.state, "none");
});

test("portal link for a Stripe subscriber; refresh from Stripe when the stored period ended", async () => {
  const t = setup();
  const key = deviceKey();
  assert.equal((await t.call("POST", "/v1/subscription/portal", { auth: key.auth })).body.error, "not_web");
  await buy(t, key);
  const sub = [...t.stripe.subscriptions.values()][0];
  sub.status = "active";
  await t.notify("customer.subscription.updated", sub);
  const portal = await t.call("POST", "/v1/subscription/portal", { auth: key.auth });
  assert.equal(portal.status, 200);
  assert.match(portal.body.url, /billing\.stripe\.com/);
  assert.equal(t.stripe.lastPortal.configuration, undefined);
  t.env.STRIPE_PORTAL_CONFIG = "bpc_test";
  await t.call("POST", "/v1/subscription/portal", { auth: key.auth });
  assert.equal(t.stripe.lastPortal.configuration, "bpc_test");

  // The renewal webhook got lost: the account asks Stripe once the stored period is over.
  t.advance(31 * DAY);
  sub.items.data[0].current_period_end = Math.floor(t.now() / 1000) + 29 * 86400;
  assert.equal((await t.call("GET", "/v1/account", { auth: key.auth })).body.state, "active");
  assert.ok(t.stripe.calls.includes(`GET /v1/subscriptions/${sub.id}`));
});

test("offer: the website price without an account; unconfigured routes say so", async () => {
  const t = setup();
  assert.deepEqual((await t.call("GET", "/v1/offer")).body, { price: { amount: "€3.49", currency: "EUR" } });
  const u = setup({ configured: false });
  const key = deviceKey();
  assert.equal((await u.call("POST", "/v1/checkout", { auth: key.auth })).body.error, "checkout_not_configured");
  assert.equal((await u.call("POST", "/v1/stripe/notifications", { raw: "{}" })).status, 503);
  assert.equal((await u.call("POST", "/v1/checkout/verify", { body: { token: "x" } })).status, 503);
});
