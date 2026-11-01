// Fernsy Control: carries recording orders, their states and the server status between the
// Fernsy apps and a Fernsy Server, and the server's pairing (openspec headless-recorder,
// design 3 and 4). It has no accounts and does not know about subscriptions: a space is named
// and guarded by values the apps derive from the user's control key, and every item is
// ciphertext the worker cannot read. Logs hold only routes, outcomes and counts, never space
// ids, secrets, codes or IP addresses. See README.md for routes and deployment.

const MINUTE = 60_000;
const HOUR = 3_600_000;
const DAY = 86_400_000;
export const LIMITS = {
  items: 500,                // live items per space
  itemBytes: 8192,           // decoded ciphertext per item
  perMinute: 120,            // requests per space and minute
  newSpacesPerHour: 10,      // per IP
  pairingPerHour: 30,        // pairing requests per IP (the server's claimed polls do not count)
  pairingMinutes: 15,
  tombstoneDays: 30,
  idleSpaceDays: 90,
};
const SPACE = /^[0-9a-f]{32}$/;
const KIND = /^[a-z][a-z-]{0,19}$/;
const ITEM_ID = /^[A-Za-z0-9_-]{1,64}$/;
const MAILBOX = /^[0-9A-HJKMNP-TV-Z]{4}$/;     // Crockford base32
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;

class HTTPError extends Error {
  constructor(status, code, message) { super(code); this.status = status; this.code = code; this.message = message; }
}

function fail(status, code, message) { throw new HTTPError(status, code, message); }

function json(status, body) {
  return new Response(body == null ? null : JSON.stringify(body), {
    status, headers: body == null ? {} : { "Content-Type": "application/json" },
  });
}

function log(fields) { console.log(JSON.stringify({ t: new Date().toISOString(), ...fields })); }

async function sha256Hex(text) {
  const bytes = typeof text === "string" ? new TextEncoder().encode(text) : text;
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function decodedLength(b64) {
  if (typeof b64 !== "string" || !BASE64.test(b64) || b64.length % 4 !== 0) return -1;
  return b64.length / 4 * 3 - (b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0);
}

function base64Field(value, name, { min = 1, max }) {
  const n = decodedLength(value);
  if (n < min || n > max) fail(n > max ? 413 : 400, n > max ? "too_large" : "bad_request", `${name} must be base64 of ${min}–${max} bytes`);
  return value;
}

async function body(request) {
  try { return await request.json(); } catch { fail(400, "bad_request", "body is not JSON"); }
}

/// Counts one request in a window; false when the limit is reached.
async function count(env, key, limit, windowMs, now) {
  const window = Math.floor(now / windowMs);
  const row = await env.DB.prepare(
    "INSERT INTO counters (key, n, expires_at) VALUES (?, 1, ?) ON CONFLICT(key) DO UPDATE SET n = n + 1 RETURNING n",
  ).bind(`${key}:${window}`, (window + 1) * windowMs).first();
  return row.n <= limit;
}

/// The client's address only as a salted hash, for the per-IP limits.
async function ipKey(request) {
  return (await sha256Hex("fernsy-control-ip:" + (request.headers.get("CF-Connecting-IP") || "unknown"))).slice(0, 16);
}

// MARK: Spaces

/// `Authorization: Space <space id>:<base64url write secret>`. An unknown space registers with
/// the secret's hash (at most `newSpacesPerHour` per IP); a known one must match it.
async function authenticate(request, env, now) {
  const m = (request.headers.get("Authorization") || "").match(/^Space ([0-9a-f]{32}):([A-Za-z0-9_-]{43})$/);
  if (!m || !SPACE.test(m[1])) fail(401, "unauthorized", "no space key");
  const hash = await sha256Hex(m[2]);
  let space = await env.DB.prepare("SELECT * FROM spaces WHERE id = ?").bind(m[1]).first();
  if (!space) {
    if (!(await count(env, `space:${await ipKey(request)}`, LIMITS.newSpacesPerHour, HOUR, now))) fail(429, "rate_limited", "too many new spaces");
    await env.DB.prepare("INSERT OR IGNORE INTO spaces (id, auth_hash, created_at, used_at) VALUES (?, ?, ?, ?)").bind(m[1], hash, now, now).run();
    space = await env.DB.prepare("SELECT * FROM spaces WHERE id = ?").bind(m[1]).first();
  }
  if (!timingSafeEqual(space.auth_hash, hash)) {
    log({ route: "auth", outcome: "rejected" });
    fail(401, "unauthorized", "wrong space key");
  }
  if (!(await count(env, `req:${space.id}`, LIMITS.perMinute, MINUTE, now))) fail(429, "rate_limited", "too many requests");
  await env.DB.prepare("UPDATE spaces SET used_at = ? WHERE id = ?").bind(now, space.id).run();
  return space;
}

async function nextChange(env, spaceId) {
  return (await env.DB.prepare("UPDATE spaces SET change = change + 1 WHERE id = ? RETURNING change").bind(spaceId).first()).change;
}

function itemJSON(row) {
  const item = { kind: row.kind, id: row.id, change: row.change, updatedAt: new Date(row.updated_at).toISOString() };
  if (row.data == null) item.deleted = true; else item.data = row.data;
  return item;
}

async function items(env, space, url) {
  const since = Number(url.searchParams.get("since") ?? 0);
  if (!Number.isInteger(since) || since < 0) fail(400, "bad_request", "since must be a change number");
  const { results } = await env.DB.prepare(
    "SELECT * FROM items WHERE space_id = ? AND change > ? ORDER BY change LIMIT ?",
  ).bind(space.id, since, LIMITS.items + 1).all();
  const more = results.length > LIMITS.items;
  const page = results.slice(0, LIMITS.items);
  return { items: page.map(itemJSON), change: more ? page[page.length - 1].change : space.change, more };
}

async function putItem(env, space, kind, id, request, now) {
  const { data } = await body(request);
  base64Field(data, "data", { max: LIMITS.itemBytes });
  const existing = await env.DB.prepare("SELECT data FROM items WHERE space_id = ? AND kind = ? AND id = ?").bind(space.id, kind, id).first();
  if (!existing || existing.data == null) {
    const live = await env.DB.prepare("SELECT COUNT(*) AS n FROM items WHERE space_id = ? AND data IS NOT NULL").bind(space.id).first();
    if (live.n >= LIMITS.items) fail(413, "full", `at most ${LIMITS.items} items`);
  }
  const change = await nextChange(env, space.id);
  await env.DB.prepare(
    "INSERT INTO items (space_id, kind, id, data, change, updated_at) VALUES (?, ?, ?, ?, ?, ?) " +
    "ON CONFLICT(space_id, kind, id) DO UPDATE SET data = excluded.data, change = excluded.change, updated_at = excluded.updated_at",
  ).bind(space.id, kind, id, data, change, now).run();
  return { change };
}

async function deleteItem(env, space, kind, id, now) {
  const existing = await env.DB.prepare("SELECT data FROM items WHERE space_id = ? AND kind = ? AND id = ?").bind(space.id, kind, id).first();
  if (!existing || existing.data == null) return { change: space.change };
  const change = await nextChange(env, space.id);
  await env.DB.prepare("UPDATE items SET data = NULL, change = ?, updated_at = ? WHERE space_id = ? AND kind = ? AND id = ?")
    .bind(change, now, space.id, kind, id).run();
  return { change };
}

async function deleteSpace(env, space) {
  await env.DB.prepare("DELETE FROM items WHERE space_id = ?").bind(space.id).run();
  await env.DB.prepare("DELETE FROM spaces WHERE id = ?").bind(space.id).run();
}

// MARK: Pairing

async function pairingLimit(request, env, now) {
  if (!(await count(env, `pair:${await ipKey(request)}`, LIMITS.pairingPerHour, HOUR, now))) fail(429, "rate_limited", "too many pairing requests");
}

async function openMailbox(env, mailbox, now) {
  const row = await env.DB.prepare("SELECT * FROM pairing WHERE mailbox = ?").bind(mailbox).first();
  if (!row || row.expires_at <= now) fail(404, "not_found", "no such pairing code");
  return row;
}

async function claim(request, row) {
  const secret = (request.headers.get("Authorization") || "").match(/^Claim ([A-Za-z0-9_-]{43})$/)?.[1];
  if (!secret || !timingSafeEqual(row.claim_hash, await sha256Hex(secret))) fail(401, "unauthorized", "wrong claim");
}

async function pairing(request, env, now, mailbox, rest) {
  const method = request.method;
  // The server's own polls carry its claim secret and do not count against the IP's limit.
  const claimed = /^Claim /.test(request.headers.get("Authorization") || "");
  if (!claimed) await pairingLimit(request, env, now);
  // The server opens a mailbox.
  if (method === "POST" && rest === "") {
    const b = await body(request);
    base64Field(b.publicKey, "publicKey", { min: 32, max: 32 });
    base64Field(b.tag, "tag", { min: 32, max: 32 });
    if (typeof b.claimHash !== "string" || !/^[0-9a-f]{64}$/.test(b.claimHash)) fail(400, "bad_request", "claimHash must be hex SHA-256");
    const expiresAt = now + LIMITS.pairingMinutes * MINUTE;
    await env.DB.prepare("DELETE FROM pairing WHERE mailbox = ? AND expires_at <= ?").bind(mailbox, now).run();
    const res = await env.DB.prepare(
      "INSERT OR IGNORE INTO pairing (mailbox, public_key, tag, claim_hash, expires_at) VALUES (?, ?, ?, ?, ?)",
    ).bind(mailbox, b.publicKey, b.tag, b.claimHash, expiresAt).run();
    if (!res.meta.changes) fail(409, "taken", "this code is in use; make a new one");
    log({ route: "pairing", outcome: "opened" });
    return json(200, { expiresAt: new Date(expiresAt).toISOString() });
  }
  const row = await openMailbox(env, mailbox, now);
  // The app reads the server's key.
  if (method === "GET" && rest === "") {
    return json(200, { publicKey: row.public_key, tag: row.tag, expiresAt: new Date(row.expires_at).toISOString() });
  }
  // The app leaves its sealed message, once.
  if (method === "PUT" && rest === "/message") {
    const b = await body(request);
    base64Field(b.message, "message", { max: LIMITS.itemBytes });
    base64Field(b.tag, "tag", { min: 32, max: 32 });
    const res = await env.DB.prepare("UPDATE pairing SET message = ?, message_tag = ? WHERE mailbox = ? AND message IS NULL")
      .bind(b.message, b.tag, mailbox).run();
    if (!res.meta.changes) fail(409, "taken", "this code has a message already");
    log({ route: "pairing", outcome: "message" });
    return json(204, null);
  }
  // The server picks the message up (or polls until it is there); taking it closes the mailbox.
  if (method === "GET" && rest === "/message") {
    await claim(request, row);
    if (row.message == null) return json(200, { message: null });
    await env.DB.prepare("DELETE FROM pairing WHERE mailbox = ?").bind(mailbox).run();
    log({ route: "pairing", outcome: "claimed" });
    return json(200, { message: row.message, tag: row.message_tag });
  }
  if (method === "DELETE" && rest === "") {
    await claim(request, row);
    await env.DB.prepare("DELETE FROM pairing WHERE mailbox = ?").bind(mailbox).run();
    return json(204, null);
  }
  fail(404, "not_found", "no such route");
}

// MARK: Routes

async function route(request, env, deps) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");
  const method = request.method;
  const now = deps.now();

  const pair = path.match(/^\/v1\/pairing\/([^/]+)(\/message)?$/);
  if (pair) {
    if (!MAILBOX.test(pair[1])) fail(400, "bad_request", "bad pairing code");
    return pairing(request, env, now, pair[1], pair[2] ?? "");
  }

  if (path === "/v1/items" && method === "GET") {
    const space = await authenticate(request, env, now);
    return json(200, await items(env, space, url));
  }
  const item = path.match(/^\/v1\/items\/([^/]+)\/([^/]+)$/);
  if (item && (method === "PUT" || method === "DELETE")) {
    if (!KIND.test(item[1]) || !ITEM_ID.test(item[2])) fail(400, "bad_request", "bad kind or id");
    const space = await authenticate(request, env, now);
    const result = method === "PUT"
      ? await putItem(env, space, item[1], item[2], request, now)
      : await deleteItem(env, space, item[1], item[2], now);
    return json(200, result);
  }
  if (path === "/v1/space" && method === "DELETE") {
    const space = await authenticate(request, env, now);
    await deleteSpace(env, space);
    log({ route: "space", outcome: "deleted" });
    return json(204, null);
  }
  fail(404, "not_found", "no such route");
}

/// Daily: expired mailboxes and counters, old tombstones, idle spaces.
export async function cleanup(env, deps) {
  const now = deps.now();
  const run = async (sql, ...args) => (await env.DB.prepare(sql).bind(...args).run()).meta.changes;
  const result = {
    pairing: await run("DELETE FROM pairing WHERE expires_at <= ?", now),
    counters: await run("DELETE FROM counters WHERE expires_at <= ?", now),
    tombstones: await run("DELETE FROM items WHERE data IS NULL AND updated_at <= ?", now - LIMITS.tombstoneDays * DAY),
    idleItems: await run("DELETE FROM items WHERE space_id IN (SELECT id FROM spaces WHERE used_at <= ?)", now - LIMITS.idleSpaceDays * DAY),
    idleSpaces: await run("DELETE FROM spaces WHERE used_at <= ?", now - LIMITS.idleSpaceDays * DAY),
  };
  log({ route: "cleanup", outcome: "ok", ...result });
  return result;
}

/// Entry point for tests: the fetch handler with injectable time.
export async function handle(request, env, deps = { now: () => Date.now() }) {
  try {
    return await route(request, env, deps);
  } catch (e) {
    if (e instanceof HTTPError) return json(e.status, { error: e.code, message: e.message });
    log({ route: new URL(request.url).pathname.split("/").slice(0, 3).join("/"), outcome: "error", error: String(e.message).slice(0, 80) });
    return json(500, { error: "internal", message: "internal error" });
  }
}

export default {
  fetch(request, env) { return handle(request, env); },
  async scheduled(event, env, ctx) { ctx.waitUntil(cleanup(env, { now: () => Date.now() })); },
};
