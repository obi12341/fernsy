// Stripe, the DMG's way to subscribe (stripe-cloud-subscription): signed webhooks, the checkout
// token the DMG passes to fernsy.app, and the API calls the worker makes (customer and
// subscription for the checkout page, customer portal, price text).
// mobilistics is the seller; the worker keeps only Stripe's ids. See design.md of the change.

import { b64urlEncode, b64urlDecode } from "./apple.js";

const API = "https://api.stripe.com/v1";
export const API_VERSION = "2025-06-30.basil";   // flexible billing mode needs basil or later
const SIGNATURE_TOLERANCE_SECONDS = 300;
export const TOKEN_SECONDS = 3600;

export class StripeNotConfigured extends Error {}
export class StripeError extends Error {
  constructor(status, code, message) { super(message || code); this.status = status; this.code = code; }
}

export function stripeConfigured(env) {
  return Boolean(env.STRIPE_SECRET_KEY && env.STRIPE_WEBHOOK_SECRET && env.STRIPE_PUBLISHABLE_KEY && env.STRIPE_PRICE_ID && env.CHECKOUT_SECRET);
}

function stripeEnv(env) { return env.STRIPE_ENV === "live" ? "live" : "test"; }

async function hmacHex(secret, text) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function equalStrings(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// `Stripe-Signature: t=…,v1=…[,v1=…]` over `t.rawBody` with the endpoint's secret, at most five
/// minutes old.
export async function verifySignature(header, rawBody, secret, nowMs) {
  if (!header || !secret) return false;
  let ts = null;
  const signatures = [];
  for (const part of header.split(",")) {
    const i = part.indexOf("=");
    const k = part.slice(0, i).trim(), v = part.slice(i + 1).trim();
    if (k === "t") ts = v;
    else if (k === "v1" && v) signatures.push(v);
  }
  if (!ts || !/^\d+$/.test(ts) || !signatures.length) return false;
  if (Math.abs(nowMs / 1000 - Number(ts)) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const expected = await hmacHex(secret, `${ts}.${rawBody}`);
  return signatures.some((s) => equalStrings(s, expected));
}

/// A checkout token: the account it is for, the environment and an expiry, signed by the worker.
/// It stands in for the account id in the browser (paddle-cloud-subscription design 2).
export async function makeCheckoutToken(env, accountId, nowMs) {
  const payload = b64urlEncode(JSON.stringify({ a: accountId, e: stripeEnv(env), x: Math.floor(nowMs / 1000) + TOKEN_SECONDS }));
  return `${payload}.${await hmacHex(env.CHECKOUT_SECRET, payload)}`;
}

/// The token's account id, or null when it is forged, expired or for the other environment.
export async function readCheckoutToken(env, token, nowMs) {
  if (typeof token !== "string" || !env.CHECKOUT_SECRET) return null;
  const [payload, sig] = token.split(".");
  if (!payload || !sig || !equalStrings(sig, await hmacHex(env.CHECKOUT_SECRET, payload))) return null;
  let data;
  try { data = JSON.parse(new TextDecoder().decode(b64urlDecode(payload))); } catch { return null; }
  if (data.e !== stripeEnv(env)) return null;
  if (!(data.x > nowMs / 1000)) return null;
  return typeof data.a === "string" ? data.a : null;
}

/// What a subscription object means for the account (design 3): null while it is not paid yet
/// (incomplete) or not one the worker created.
export function subscriptionStatus(sub, nowMs) {
  if (!sub || typeof sub.id !== "string" || !sub.id.startsWith("sub_")) return null;
  const accountId = sub.metadata?.fernsy_account;
  if (typeof accountId !== "string" || !accountId) return null;
  const item = sub.items?.data?.[0];
  const periodEnd = item?.current_period_end ?? sub.current_period_end ?? null;
  const iso = (seconds) => new Date(seconds * 1000).toISOString();
  let expiresAt;
  switch (sub.status) {
    case "active":
    case "trialing":
    case "past_due":
      expiresAt = periodEnd ? iso(periodEnd) : new Date(nowMs).toISOString();
      break;
    case "canceled":
      expiresAt = iso(sub.ended_at ?? sub.canceled_at ?? Math.floor(nowMs / 1000));
      break;
    case "unpaid":
    case "paused":
      expiresAt = new Date(nowMs).toISOString();
      break;
    default:   // incomplete, incomplete_expired: never paid
      return null;
  }
  return {
    originalTransactionId: sub.id,
    productId: item?.price?.id ?? null,
    expiresAt,
    customerId: typeof sub.customer === "string" ? sub.customer : sub.customer?.id ?? null,
    accountId,
    cancelAtPeriodEnd: Boolean(sub.cancel_at_period_end),
  };
}

/// Stripe's form encoding: nested objects and arrays as `a[b][0]=…`.
export function formEncode(value, prefix = "", out = []) {
  if (value === undefined || value === null) return out;
  if (Array.isArray(value)) value.forEach((v, i) => formEncode(v, `${prefix}[${i}]`, out));
  else if (typeof value === "object") for (const [k, v] of Object.entries(value)) formEncode(v, prefix ? `${prefix}[${k}]` : k, out);
  else out.push(`${encodeURIComponent(prefix)}=${encodeURIComponent(String(value))}`);
  return out;
}

async function api(env, deps, method, path, params, { idempotencyKey } = {}) {
  if (!env.STRIPE_SECRET_KEY) throw new StripeNotConfigured();
  const query = method === "GET" && params ? `?${formEncode(params).join("&")}` : "";
  const res = await deps.fetch(`${API}${path}${query}`, {
    method,
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`, "Stripe-Version": API_VERSION,
      ...(method === "GET" ? {} : { "Content-Type": "application/x-www-form-urlencoded" }),
      ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}),
    },
    body: method === "GET" ? undefined : formEncode(params ?? {}).join("&"),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new StripeError(res.status, data.error?.code ?? data.error?.type ?? "stripe_error", data.error?.message);
  return data;
}

export function getSubscription(env, deps, id) { return api(env, deps, "GET", `/subscriptions/${encodeURIComponent(id)}`); }

/// The checkout page's purchase (design 2): a customer with the buyer's e-mail and location for
/// Stripe Tax, and an incomplete subscription for the account whose first invoice the page pays.
export async function createSubscription(env, deps, { accountId, email, country, postalCode, consentAt, locale }) {
  const customer = await api(env, deps, "POST", "/customers", {
    email, address: { country, postal_code: postalCode }, tax: { validate_location: "immediately" },
    preferred_locales: locale ? [locale] : undefined,   // receipts and portal in the buyer's language
    metadata: { fernsy_account: accountId },
  });
  const sub = await api(env, deps, "POST", "/subscriptions", {
    customer: customer.id,
    items: [{ price: env.STRIPE_PRICE_ID }],
    payment_behavior: "default_incomplete",
    billing_mode: { type: "flexible" },
    automatic_tax: { enabled: true },
    payment_settings: { save_default_payment_method: "on_subscription" },
    metadata: { fernsy_account: accountId, start_consent_at: consentAt },
    expand: ["latest_invoice.confirmation_secret"],
  });
  return { subscriptionId: sub.id, clientSecret: sub.latest_invoice?.confirmation_secret?.client_secret ?? null };
}

/// A short-lived link to the customer portal (design 4).
export async function portalURL(env, deps, customerId) {
  const session = await api(env, deps, "POST", "/billing_portal/sessions", {
    customer: customerId, return_url: "https://www.fernsy.app/", configuration: env.STRIPE_PORTAL_CONFIG || undefined,
  });
  return session.url ?? null;
}

/// The price as the buyer sees it ("€3.49"), from the price object; null when unknown.
export async function priceText(env, deps) {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_PRICE_ID) return null;
  try {
    const price = await api(env, deps, "GET", `/prices/${encodeURIComponent(env.STRIPE_PRICE_ID)}`);
    if (typeof price.unit_amount !== "number" || !price.currency) return null;
    const currency = price.currency.toUpperCase();
    const amount = new Intl.NumberFormat("en", { style: "currency", currency }).format(price.unit_amount / 100);
    return { amount, currency };
  } catch {
    return null;
  }
}
