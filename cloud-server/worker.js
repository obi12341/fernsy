// Fernsy Cloud: private, end-to-end encrypted recording storage (openspec cloud-server).
// The apps upload and stream ciphertext directly with R2 through short-lived signed URLs;
// this worker only knows accounts by a hash of their key-derived access secret, checks their
// subscription with Apple, keeps the quota and hands out those URLs. It never sees keys, titles or other readable recording details, and
// it never logs signed URLs. See README.md for routes, bindings and deployment.

import { presign, signedHeaders, objectURL } from "./sigv4.js";
import {
  AppleNotConfigured, b64urlDecode, subscriptionStatus, appStoreConfigured, notificationTransactionId,
} from "./apple.js";
import * as store from "./store.js";

const MiB = 1048576;
const MIN_PART = 5 * MiB;
const MAX_PARTS = 10000;
const MAX_META = MiB;
const FIRST_PART_URLS = 20;      // more through /parts: signing all parts of a 3 GB file costs CPU time
const MAX_PART_URLS = 50;
const UPLOAD_URL_SECONDS = 3600;
const READ_URL_SECONDS = 6 * 3600;
const GRACE_DAYS = 30;
const ABANDON_DAYS = 7;
const DEFAULT_QUOTA = 250 * 1000 ** 3;
const DEFAULT_PRODUCT = "de.mobilistics.fernsy.cloud.monthly";
const ACCOUNT_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

class HTTPError extends Error {
  constructor(status, code, extra = {}) { super(code); this.status = status; this.code = code; this.extra = extra; }
}

function json(status, body, headers = {}) {
  return new Response(body == null ? null : JSON.stringify(body), {
    status, headers: body == null ? headers : { "Content-Type": "application/json", ...headers },
  });
}

function fail(status, code, message, extra = {}) { throw new HTTPError(status, code, { message, ...extra }); }

// Only ids, sizes, times and outcomes (cloud-server "No keys or readable content").
function log(fields) { console.log(JSON.stringify({ t: new Date().toISOString(), ...fields })); }

function bundleIds(env) { return (env.BUNDLE_IDS || "de.mobilistics.fernsy,de.mobilistics.fernsy.dev").split(",").map((s) => s.trim()); }
function quotaOf(env, user) { return Number(user.quota_bytes ?? env.QUOTA_BYTES ?? DEFAULT_QUOTA); }
function dataKey(userId, id) { return `u/${userId}/${id}.data`; }
function metaKey(userId, id) { return `u/${userId}/${id}.meta`; }
function s3(env) { return { accessKeyId: env.S3_KEY, secret: env.S3_SECRET }; }
function url(env, key) { return objectURL(env.ACCOUNT_ID, env.BUCKET_NAME, key); }

function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function body(request) {
  try { return await request.json(); } catch { fail(400, "bad_request", "body is not JSON"); }
}

// MARK: S3 calls of the worker itself

async function s3Fetch(deps, env, method, target, payload = "") {
  const headers = await signedHeaders({ method, url: target, body: payload, ...s3(env), date: new Date(deps.now()) });
  const res = await deps.fetch(target, { method, headers, body: payload || undefined });
  const text = await res.text();
  if (!res.ok || text.includes("<Error>")) throw new Error(`s3 ${method} ${res.status}`);
  return text;
}

async function createMultipart(deps, env, key) {
  const xml = await s3Fetch(deps, env, "POST", url(env, key) + "?uploads");
  const m = xml.match(/<UploadId>([^<]+)<\/UploadId>/);
  if (!m) throw new Error("s3 create: no upload id");
  return m[1];
}

async function completeMultipart(deps, env, key, uploadId, parts) {
  const xml = "<CompleteMultipartUpload>" + parts
    .map((p) => `<Part><PartNumber>${p.number}</PartNumber><ETag>${String(p.etag).replace(/[<>&]/g, "")}</ETag></Part>`)
    .join("") + "</CompleteMultipartUpload>";
  await s3Fetch(deps, env, "POST", `${url(env, key)}?uploadId=${encodeURIComponent(uploadId)}`, xml);
}

async function abortMultipart(deps, env, key, uploadId) {
  try { await s3Fetch(deps, env, "DELETE", `${url(env, key)}?uploadId=${encodeURIComponent(uploadId)}`); }
  catch { /* already gone */ }
}

async function partURLs(deps, env, key, uploadId, numbers) {
  return Promise.all(numbers.map(async (number) => ({
    number,
    url: await presign({ method: "PUT", url: `${url(env, key)}?partNumber=${number}&uploadId=${encodeURIComponent(uploadId)}`,
      expires: UPLOAD_URL_SECONDS, ...s3(env), date: new Date(deps.now()) }),
  })));
}

/// Removes a recording completely: unfinished upload, objects and row.
async function removeRecording(deps, env, rec) {
  if (rec.upload_id) await abortMultipart(deps, env, dataKey(rec.user_id, rec.id), rec.upload_id);
  await env.BUCKET.delete([dataKey(rec.user_id, rec.id), metaKey(rec.user_id, rec.id)]);
  await store.deleteRecordingRow(env.DB, rec.id);
}

// MARK: Auth

async function sha256Hex(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) => x.toString(16).padStart(2, "0")).join("");
}

/// `Authorization: Key <accountId>:<base64url secret>` (cloud-account-from-icloud-key design
/// A, B): an unknown account id registers with the secret's hash; a known one must match it.
/// On the dev deployment `Authorization: Dev <DEV_TOKEN>` stands for the dev user.
async function authenticate(request, env, deps) {
  const header = request.headers.get("Authorization") || "";
  if (env.DEV_TOKEN && header.startsWith("Dev ")) {
    if (!timingSafeEqual(header.slice(4), env.DEV_TOKEN)) fail(401, "unauthorized", "bad dev token");
    return { user: await store.ensureDevUser(env.DB, deps.now()), dev: true };
  }
  const m = header.match(/^Key ([^:\s]+):([A-Za-z0-9_-]+)$/);
  if (!m || !ACCOUNT_ID.test(m[1])) fail(401, "unauthorized", "no account key");
  let secret;
  try { secret = b64urlDecode(m[2]); } catch { fail(401, "unauthorized", "no account key"); }
  if (secret.length !== 32) fail(401, "unauthorized", "no account key");
  const hash = await sha256Hex(secret);
  let user = await store.registerAccount(env.DB, m[1], hash, deps.now());
  if (!user || !timingSafeEqual(user.auth_hash, hash)) {
    log({ route: "auth", outcome: "rejected" });
    fail(401, "unauthorized", "wrong account key");
  }
  // Take-back (design E): a subscription bought for this account comes home.
  if ((await store.takeBack(env.DB, user, deps.now())).length) {
    log({ route: "takeback", user: user.id, outcome: "linked" });
    user = await store.userById(env.DB, user.id);
  }
  return { user };
}

// MARK: Account and subscription

/// Asks Apple about one subscription and stores the answer; errors are logged and ignored.
async function refreshSubscription(deps, env, originalTransactionId, userId) {
  if (!appStoreConfigured(env) || !originalTransactionId || originalTransactionId.startsWith("dev:")) return;
  try {
    const status = await subscriptionStatus(env, originalTransactionId, deps.fetch, deps.now());
    if (status) await store.updateSubscription(env.DB, originalTransactionId, status);
  } catch (e) {
    log({ route: "refresh", user: userId ?? undefined, outcome: "apple_error" });
  }
}

async function refreshFromApple(deps, env, user) {
  await refreshSubscription(deps, env, user.original_transaction_id, user.id);
  return store.userById(env.DB, user.id);
}

async function accountJSON(env, user, now) {
  const graceDays = Number(env.GRACE_DAYS ?? GRACE_DAYS);
  return { userId: user.account_id === "dev" ? user.id : user.account_id, ...store.accountState(user, now, graceDays), usedBytes: await store.usedBytes(env.DB, user.id), totalBytes: quotaOf(env, user) };
}

function requireState(env, user, now, allowed) {
  const { state } = store.accountState(user, now, Number(env.GRACE_DAYS ?? GRACE_DAYS));
  if (!allowed.includes(state)) fail(402, "no_subscription", `subscription is ${state}`);
}

// MARK: Routes

async function route(request, env, deps) {
  const u = new URL(request.url);
  const path = u.pathname.replace(/\/+$/, "");
  const method = request.method;
  const now = deps.now();

  if (method === "POST" && path === "/v1/apple/notifications") {
    const { signedPayload } = await body(request);
    let id = null;
    try { id = notificationTransactionId(signedPayload); } catch { /* ignored below */ }
    if (!id) return json(200, {});
    if (!appStoreConfigured(env)) fail(503, "apple_not_configured", "App Store Server API is not configured");
    const status = await subscriptionStatus(env, id, deps.fetch, now);
    if (status) await store.updateSubscription(env.DB, id, status);
    log({ route: "notification", outcome: status ? "updated" : "unknown" });
    return json(200, {});
  }

  const auth = await authenticate(request, env, deps);
  let user = auth.user;
  const reply = (status, b) => json(status, b);

  if (method === "GET" && path === "/v1/account") {
    if (user.expires_at && Date.parse(user.expires_at) <= now && !user.revoked_at) user = await refreshFromApple(deps, env, user);
    return reply(200, await accountJSON(env, user, now));
  }

  if (method === "POST" && path === "/v1/subscription") {
    const { originalTransactionId, move } = await body(request);
    if (!originalTransactionId) fail(400, "bad_request", "originalTransactionId missing");
    if (auth.dev) fail(400, "bad_request", "the dev user has no App Store subscription");
    if (!appStoreConfigured(env)) fail(503, "apple_not_configured", "App Store Server API is not configured");
    const status = await subscriptionStatus(env, String(originalTransactionId), deps.fetch, now);
    if (!status) fail(404, "not_found", "Apple does not know this transaction");
    if (!bundleIds(env).includes(status.bundleId) || status.productId !== (env.PRODUCT_ID || DEFAULT_PRODUCT)) {
      fail(400, "wrong_product", "not a Fernsy Cloud subscription");
    }
    // Bound by the purchase's appAccountToken (design C); anything else only on an explicit move (E).
    const own = status.appAccountToken === user.account_id;
    if (!own && move !== true) {
      log({ route: "subscription", user: user.id, outcome: "other_account" });
      fail(409, "other_account", "this subscription was bought for another account");
    }
    const previous = await store.linkSubscription(env.DB, user.id, status, now);
    log({ route: "subscription", user: user.id, outcome: own ? "linked" : previous ? "moved" : "moved_unlinked" });
    return reply(200, await accountJSON(env, await store.userById(env.DB, user.id), now));
  }

  if (method === "GET" && path === "/v1/recordings") {
    const rows = await store.doneRecordings(env.DB, user.id);
    return reply(200, { recordings: rows.map((r) => ({ id: r.id, dataBytes: r.data_bytes, metaBytes: r.meta_bytes, completedAt: r.completed_at })) });
  }

  if (method === "POST" && path === "/v1/recordings") {
    requireState(env, user, now, ["active"]);
    const b = await body(request);
    const dataBytes = Number(b.dataBytes), metaBytes = Number(b.metaBytes), partSize = Number(b.partSize);
    if (!(Number.isInteger(dataBytes) && dataBytes > 0)) fail(400, "bad_request", "dataBytes");
    if (!(Number.isInteger(metaBytes) && metaBytes > 0 && metaBytes <= MAX_META)) fail(400, "bad_request", "metaBytes");
    if (!(Number.isInteger(partSize) && partSize >= MIN_PART)) fail(400, "bad_request", "partSize below 5 MiB");
    const partCount = Math.ceil(dataBytes / partSize);
    if (partCount > MAX_PARTS) fail(400, "bad_request", "too many parts");
    const id = crypto.randomUUID();
    const quota = quotaOf(env, user);
    if (!(await store.reserveRecording(env.DB, { id, userId: user.id, dataBytes, metaBytes, partSize, quota, now }))) {
      const free = Math.max(0, quota - (await store.usedBytes(env.DB, user.id)));
      log({ route: "start", user: user.id, bytes: dataBytes, outcome: "quota" });
      fail(413, "quota", "not enough free storage", { neededBytes: dataBytes + metaBytes, freeBytes: free });
    }
    let uploadId;
    try { uploadId = await createMultipart(deps, env, dataKey(user.id, id)); }
    catch (e) { await store.deleteRecordingRow(env.DB, id); throw e; }
    await store.setUploadId(env.DB, id, uploadId);
    const numbers = Array.from({ length: Math.min(partCount, FIRST_PART_URLS) }, (_, i) => i + 1);
    const metaURL = await presign({ method: "PUT", url: url(env, metaKey(user.id, id)), expires: UPLOAD_URL_SECONDS, ...s3(env), date: new Date(now) });
    log({ route: "start", user: user.id, rec: id, bytes: dataBytes, outcome: "ok" });
    return reply(200, { id, uploadId, partSize, partCount, partURLs: await partURLs(deps, env, dataKey(user.id, id), uploadId, numbers), metaURL });
  }

  const m = path.match(/^\/v1\/recordings\/([0-9a-f-]{36})(\/parts|\/complete|\/urls)?$/);
  if (m) {
    const rec = await store.recording(env.DB, user.id, m[1]);
    if (!rec) fail(404, "not_found", "no such recording");
    const action = m[2];

    if (method === "POST" && action === "/parts") {
      requireState(env, user, now, ["active"]);
      if (rec.state !== "uploading") fail(409, "not_uploading", "upload already finished");
      const partCount = Math.ceil(rec.data_bytes / rec.part_size);
      const b = await body(request);
      const numbers = [...new Set(b.numbers || [])].map(Number);
      const wantsMeta = b.meta === true;
      if ((!numbers.length && !wantsMeta) || numbers.length > MAX_PART_URLS || numbers.some((n) => !Number.isInteger(n) || n < 1 || n > partCount)) {
        fail(400, "bad_request", `up to ${MAX_PART_URLS} part numbers between 1 and ${partCount}, or meta`);
      }
      const answer = { partURLs: await partURLs(deps, env, dataKey(user.id, rec.id), rec.upload_id, numbers) };
      // A resumed upload may send the details again.
      if (wantsMeta) answer.metaURL = await presign({ method: "PUT", url: url(env, metaKey(user.id, rec.id)), expires: UPLOAD_URL_SECONDS, ...s3(env), date: new Date(now) });
      return reply(200, answer);
    }

    if (method === "POST" && action === "/complete") {
      if (rec.state !== "uploading") fail(409, "not_uploading", "upload already finished");
      const parts = ((await body(request)).parts || []).map((p) => ({ number: Number(p.number), etag: String(p.etag) }))
        .sort((a, b) => a.number - b.number);
      const partCount = Math.ceil(rec.data_bytes / rec.part_size);
      if (parts.length !== partCount || parts.some((p, i) => p.number !== i + 1)) fail(400, "bad_request", `expected parts 1 to ${partCount}`);
      try { await completeMultipart(deps, env, dataKey(user.id, rec.id), rec.upload_id, parts); }
      catch { log({ route: "complete", user: user.id, rec: rec.id, outcome: "s3_rejected" }); fail(400, "incomplete", "storage rejected the parts"); }
      const data = await env.BUCKET.head(dataKey(user.id, rec.id));
      const meta = await env.BUCKET.head(metaKey(user.id, rec.id));
      if (!data || !meta) {
        await removeRecording(deps, env, { ...rec, upload_id: null });
        fail(400, "incomplete", meta ? "data missing" : "details missing");
      }
      const others = (await store.usedBytes(env.DB, user.id)) - rec.data_bytes - rec.meta_bytes;
      if (data.size + meta.size > rec.data_bytes + rec.meta_bytes && others + data.size + meta.size > quotaOf(env, user)) {
        await removeRecording(deps, env, { ...rec, upload_id: null });
        log({ route: "complete", user: user.id, rec: rec.id, bytes: data.size, outcome: "quota" });
        fail(413, "quota", "larger than stated and over quota", { neededBytes: data.size + meta.size, freeBytes: Math.max(0, quotaOf(env, user) - others) });
      }
      await store.completeRecording(env.DB, rec.id, { dataBytes: data.size, metaBytes: meta.size, now });
      log({ route: "complete", user: user.id, rec: rec.id, bytes: data.size, outcome: "ok" });
      return reply(200, { id: rec.id, dataBytes: data.size });
    }

    if (method === "GET" && action === "/urls") {
      requireState(env, user, now, ["active", "grace"]);
      if (rec.state !== "done") fail(409, "not_done", "upload not finished");
      const date = new Date(now);
      const [dataURL, metaURL] = await Promise.all([dataKey, metaKey].map((k) =>
        presign({ method: "GET", url: url(env, k(user.id, rec.id)), expires: READ_URL_SECONDS, ...s3(env), date })));
      log({ route: "urls", user: user.id, rec: rec.id, outcome: "ok" });
      return reply(200, { dataURL, metaURL, expiresAt: store.iso(now + READ_URL_SECONDS * 1000) });
    }

    if (method === "DELETE" && !action) {
      await removeRecording(deps, env, rec);
      log({ route: "delete", user: user.id, rec: rec.id, bytes: rec.data_bytes, outcome: "ok" });
      return new Response(null, { status: 204 });
    }
  }

  if (method === "DELETE" && path === "/v1/account") {
    // Design G: objects and rows go; the subscriptions stay for the next registration.
    const recs = await store.recordingsOf(env.DB, user.id);
    for (const rec of recs) await removeRecording(deps, env, rec);
    await store.deleteAccount(env.DB, user.id);
    log({ route: "delete_account", user: user.id, outcome: "ok" });
    return new Response(null, { status: 204 });
  }

  if (auth.dev && method === "POST" && path === "/v1/dev/account") {
    const b = await body(request);
    const state = b.state;
    const expiresAt = state === "none" ? null
      : state === "active" ? store.iso(now + 3650 * store.DAY)
      : state === "ended" ? store.iso(now - Number(b.endedDaysAgo ?? 0) * store.DAY)
      : fail(400, "bad_request", "state is none, active or ended");
    await store.setDevState(env.DB, user.id, { expiresAt, quotaBytes: b.quotaBytes });
    return reply(200, await accountJSON(env, await store.userById(env.DB, user.id), now));
  }

  if (auth.dev && method === "POST" && path === "/v1/dev/cron") {
    const b = await body(request);
    return reply(200, await cleanup(env, deps, { abandonDays: b.abandonDays, graceDays: b.graceDays }));
  }

  fail(404, "not_found", "no such route");
}

// MARK: Cleanup (daily cron)

export async function cleanup(env, deps, { abandonDays, graceDays } = {}) {
  const now = deps.now();
  const result = { abortedUploads: 0, deletedUsers: 0, refreshed: 0 };
  for (const rec of await store.abandonedUploads(env.DB, now - Number(abandonDays ?? ABANDON_DAYS) * store.DAY)) {
    await removeRecording(deps, env, rec);
    result.abortedUploads++;
  }
  if (appStoreConfigured(env)) {
    for (const sub of await store.staleSubscriptions(env.DB, now)) {
      await refreshSubscription(deps, env, sub.original_transaction_id, sub.user_id);
      result.refreshed++;
    }
  }
  for (const user of await store.expiredUsersWithData(env.DB, now, Number(graceDays ?? env.GRACE_DAYS ?? GRACE_DAYS))) {
    for (const rec of await store.recordingsOf(env.DB, user.id)) await removeRecording(deps, env, rec);
    result.deletedUsers++;
  }
  log({ route: "cleanup", outcome: "ok", ...result });
  return result;
}

/// Entry point for tests: the fetch handler with injectable time and network.
export async function handle(request, env, deps = { fetch: (...a) => fetch(...a), now: () => Date.now() }) {
  try {
    return await route(request, env, deps);
  } catch (e) {
    if (e instanceof HTTPError) return json(e.status, { error: e.code, ...e.extra });
    if (e instanceof AppleNotConfigured) return json(503, { error: "apple_not_configured", message: "App Store Server API is not configured" });
    log({ route: new URL(request.url).pathname.replace(/[0-9a-f-]{36}/g, ":id"), outcome: "error", error: String(e.message).slice(0, 80) });
    return json(500, { error: "internal", message: "internal error" });
  }
}

export default {
  fetch(request, env) { return handle(request, env); },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(cleanup(env, { fetch: (...a) => fetch(...a), now: () => Date.now() }));
  },
};
