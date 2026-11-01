// Paddle, the second way to subscribe (paddle-cloud-subscription): signed webhooks, the checkout
// token the DMG passes to fernsy.app, and the few API calls the worker makes (subscription,
// customer portal, price preview). Paddle is merchant of record; the worker keeps only Paddle's
// ids. See design.md of the change for the reasons.

import { b64urlEncode, b64urlDecode } from "./apple.js";

const SIGNATURE_TOLERANCE_SECONDS = 300;
export const TOKEN_SECONDS = 3600;

export class PaddleNotConfigured extends Error {}

export function paddleConfigured(env) { return Boolean(env.PADDLE_WEBHOOK_SECRET && env.CHECKOUT_SECRET && env.PADDLE_PRICE_ID); }

function apiBase(env) { return env.PADDLE_ENV === "live" ? "https://api.paddle.com" : "https://sandbox-api.paddle.com"; }

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

/// `Paddle-Signature: ts=…;h1=…[;h1=…]` over `ts:rawBody` with the destination's secret, at most
/// five minutes old (Paddle retries send a fresh signature).
export async function verifySignature(header, rawBody, secret, nowMs) {
  if (!header || !secret) return false;
  let ts = null;
  const signatures = [];
  for (const part of header.split(";")) {
    const [k, v] = part.split("=");
    if (k === "ts") ts = v;
    else if (k === "h1" && v) signatures.push(v);
  }
  if (!ts || !/^\d+$/.test(ts) || !signatures.length) return false;
  if (Math.abs(nowMs / 1000 - Number(ts)) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const expected = await hmacHex(secret, `${ts}:${rawBody}`);
  return signatures.some((s) => equalStrings(s, expected));
}

/// A checkout token: the account it is for, the environment and an expiry, signed by the worker.
/// It stands in for the account id in the browser and in Paddle's custom data (design 2).
export async function makeCheckoutToken(env, accountId, nowMs) {
  const payload = b64urlEncode(JSON.stringify({ a: accountId, e: env.PADDLE_ENV === "live" ? "live" : "sandbox", x: Math.floor(nowMs / 1000) + TOKEN_SECONDS }));
  return `${payload}.${await hmacHex(env.CHECKOUT_SECRET, payload)}`;
}

/// The token's account id, or null when it is forged or for another environment. `ignoreExpiry`
/// for webhooks: a renewal months later still carries the token of the first checkout.
export async function readCheckoutToken(env, token, nowMs, { ignoreExpiry = false } = {}) {
  if (typeof token !== "string" || !env.CHECKOUT_SECRET) return null;
  const [payload, sig] = token.split(".");
  if (!payload || !sig || !equalStrings(sig, await hmacHex(env.CHECKOUT_SECRET, payload))) return null;
  let data;
  try { data = JSON.parse(new TextDecoder().decode(b64urlDecode(payload))); } catch { return null; }
  if (data.e !== (env.PADDLE_ENV === "live" ? "live" : "sandbox")) return null;
  if (!ignoreExpiry && !(data.x > nowMs / 1000)) return null;
  return typeof data.a === "string" ? data.a : null;
}

/// What a subscription entity means for the account (design 3): null for events that change
/// nothing about access.
export function subscriptionStatus(sub, nowMs) {
  if (!sub || typeof sub.id !== "string" || !sub.id.startsWith("sub_")) return null;
  const periodEnd = sub.current_billing_period?.ends_at ?? sub.next_billed_at ?? null;
  let expiresAt;
  switch (sub.status) {
    case "active":
    case "trialing":
    case "past_due":
      expiresAt = periodEnd ?? new Date(nowMs).toISOString();
      break;
    case "canceled":
      expiresAt = sub.canceled_at ?? new Date(nowMs).toISOString();
      break;
    case "paused":
      expiresAt = sub.paused_at ?? new Date(nowMs).toISOString();
      break;
    default:
      return null;
  }
  return {
    originalTransactionId: sub.id,
    productId: sub.items?.[0]?.price?.id ?? null,
    expiresAt,
    revokedAt: null,
    customerId: sub.customer_id ?? null,
    checkoutToken: sub.custom_data?.fernsy_checkout ?? null,
  };
}

async function api(env, deps, method, path, payload) {
  if (!env.PADDLE_API_KEY) throw new PaddleNotConfigured();
  const res = await deps.fetch(`${apiBase(env)}${path}`, {
    method,
    headers: { Authorization: `Bearer ${env.PADDLE_API_KEY}`, "Content-Type": "application/json" },
    body: payload === undefined ? undefined : JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`paddle ${method} ${path.split("/")[1]} ${res.status}`);
  return (await res.json()).data;
}

export function getSubscription(env, deps, id) { return api(env, deps, "GET", `/subscriptions/${encodeURIComponent(id)}`); }

/// An authenticated link to the customer portal for this subscription (design 4).
export async function portalURL(env, deps, customerId, subscriptionId) {
  const session = await api(env, deps, "POST", `/customers/${encodeURIComponent(customerId)}/portal-sessions`,
    { subscription_ids: subscriptionId ? [subscriptionId] : [] });
  return session.urls?.general?.overview ?? null;
}

/// The price as the customer's country sees it, for the DMG's offer; null when unknown.
export async function pricePreview(env, deps, countryCode) {
  if (!env.PADDLE_API_KEY) return null;
  try {
    const preview = await api(env, deps, "POST", "/pricing-preview", {
      items: [{ price_id: env.PADDLE_PRICE_ID, quantity: 1 }],
      ...(countryCode ? { address: { country_code: countryCode } } : {}),
    });
    const line = preview.details?.line_items?.[0];
    return line ? { amount: line.formatted_totals?.total ?? null, currency: preview.currency_code } : null;
  } catch {
    return null;
  }
}
