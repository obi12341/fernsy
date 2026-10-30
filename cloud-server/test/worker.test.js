import test from "node:test";
import assert from "node:assert/strict";
import { makeDB, makeStorage } from "./d1.js";
import { handle, cleanup } from "../worker.js";
import { b64urlEncode } from "../apple.js";
import * as store from "../store.js";

const MiB = 1048576;
const PART = 5 * MiB;

/// A device's credential as the apps derive it from the cloud key: a lowercase UUID and 32
/// random bytes.
function deviceKey() {
  const accountId = crypto.randomUUID();
  const secret = b64urlEncode(crypto.getRandomValues(new Uint8Array(32)));
  return { accountId, secret, auth: `Key ${accountId}:${secret}` };
}

function jws(payload) { return `${b64urlEncode('{"alg":"ES256"}')}.${b64urlEncode(JSON.stringify(payload))}.sig`; }

async function appStoreKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  return { APPSTORE_KEY: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----`, APPSTORE_KEY_ID: "KID", APPSTORE_ISSUER: "ISS" };
}

function setup({ quota } = {}) {
  const storage = makeStorage();
  let now = Date.parse("2026-10-30T12:00:00Z");
  const env = { DB: makeDB(), BUCKET: storage.bucket, ACCOUNT_ID: "acc", BUCKET_NAME: "b", S3_KEY: "k", S3_SECRET: "s",
    DEV_TOKEN: "devtoken", QUOTA_BYTES: String(quota ?? 1000 * MiB) };
  // Apple's App Store Server API (sandbox) answers from `apple`: transaction id -> transaction info.
  const apple = new Map();
  const fetchFn = async (url, init) => {
    if (String(url).includes("storekit")) {
      if (String(url).includes("storekit.itunes")) return new Response("", { status: 401 });
      const id = decodeURIComponent(String(url).split("/").pop());
      const info = apple.get(id);
      if (!info) return new Response("", { status: 404 });
      return Response.json({ data: [{ lastTransactions: [{ originalTransactionId: id,
        signedTransactionInfo: jws({ originalTransactionId: id, bundleId: "de.mobilistics.fernsy", productId: "de.mobilistics.fernsy.cloud.monthly",
          expiresDate: now + 30 * store.DAY, ...info }) }] }] });
    }
    return storage.fetch(url, init);
  };
  const deps = { fetch: fetchFn, now: () => now };
  const call = async (method, path, { body, auth = "Dev devtoken" } = {}) => {
    const res = await handle(new Request("https://cloud.test" + path, {
      method, headers: auth ? { Authorization: auth } : {}, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, deps);
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  };
  return { env, deps, storage, apple, call, advance: (ms) => { now += ms; }, now: () => now };
}

async function upload(t, dataBytes, { complete = true } = {}) {
  const start = await t.call("POST", "/v1/recordings", { body: { dataBytes, metaBytes: 100, partSize: PART } });
  if (start.status !== 200) return { start };
  const parts = [];
  for (const { number, url } of start.body.partURLs) {
    const size = number < start.body.partCount ? PART : dataBytes - PART * (start.body.partCount - 1);
    const res = await t.storage.fetch(url, { method: "PUT", body: new Uint8Array(size).fill(number) });
    parts.push({ number, etag: res.headers.get("etag") });
  }
  await t.storage.fetch(start.body.metaURL, { method: "PUT", body: new Uint8Array(100) });
  if (!complete) return { start };
  const done = await t.call("POST", `/v1/recordings/${start.body.id}/complete`, { body: { parts } });
  return { start, done };
}

test("upload, list, stream URLs and delete", async () => {
  const t = setup();
  const { start, done } = await upload(t, 2 * PART + 100);
  assert.equal(start.body.partCount, 3);
  assert.equal(start.body.partURLs.length, 3);
  assert.match(start.body.partURLs[0].url, /^https:\/\/acc\.r2\.cloudflarestorage\.com\/b\/u\/[0-9a-f-]+\/[0-9a-f-]+\.data\?.*&partNumber=1&uploadId=up1&/);
  assert.equal(done.status, 200);
  assert.equal(done.body.dataBytes, 2 * PART + 100);
  const list = await t.call("GET", "/v1/recordings");
  assert.equal(list.body.recordings.length, 1);
  assert.equal(list.body.recordings[0].dataBytes, 2 * PART + 100);
  const urls = await t.call("GET", `/v1/recordings/${start.body.id}/urls`);
  assert.equal(urls.status, 200);
  assert.match(urls.body.dataURL, /X-Amz-Expires=21600/);
  const account = await t.call("GET", "/v1/account");
  assert.equal(account.body.state, "active");
  assert.equal(account.body.usedBytes, 2 * PART + 200);
  assert.ok(account.body.userId);
  assert.equal((await t.call("DELETE", `/v1/recordings/${start.body.id}`)).status, 204);
  assert.equal(t.storage.bucket.objects.size, 0);
  assert.equal((await t.call("GET", "/v1/account")).body.usedBytes, 0);
});

test("only the first 20 part URLs at start, the rest through /parts", async () => {
  const t = setup();
  const start = await t.call("POST", "/v1/recordings", { body: { dataBytes: 30 * PART, metaBytes: 100, partSize: PART } });
  assert.equal(start.body.partCount, 30);
  assert.equal(start.body.partURLs.length, 20);
  const more = await t.call("POST", `/v1/recordings/${start.body.id}/parts`, { body: { numbers: [21, 30] } });
  assert.deepEqual(more.body.partURLs.map((p) => p.number), [21, 30]);
  assert.equal((await t.call("POST", `/v1/recordings/${start.body.id}/parts`, { body: { numbers: [31] } })).status, 400);
  assert.equal((await t.call("POST", `/v1/recordings/${start.body.id}/parts`, { body: { numbers: [] } })).status, 400);
  const meta = await t.call("POST", `/v1/recordings/${start.body.id}/parts`, { body: { numbers: [], meta: true } });
  assert.equal(meta.status, 200);
  assert.deepEqual(meta.body.partURLs, []);
  assert.match(meta.body.metaURL, /\.meta\?/);
});

test("over quota is refused with needed and free bytes", async () => {
  const t = setup({ quota: 20 * MiB });
  await upload(t, 2 * PART);
  const res = await t.call("POST", "/v1/recordings", { body: { dataBytes: 3 * PART, metaBytes: 100, partSize: PART } });
  assert.equal(res.status, 413);
  assert.equal(res.body.error, "quota");
  assert.equal(res.body.neededBytes, 3 * PART + 100);
  assert.equal(res.body.freeBytes, 20 * MiB - 2 * PART - 100);
});

test("a part size below 5 MiB is refused", async () => {
  const t = setup();
  assert.equal((await t.call("POST", "/v1/recordings", { body: { dataBytes: 10, metaBytes: 1, partSize: MiB } })).status, 400);
});

test("another user's recording answers 404", async () => {
  const t = setup();
  const { start } = await upload(t, PART + 1);
  const { auth } = deviceKey();
  for (const [m, p] of [["GET", "/urls"], ["DELETE", ""], ["POST", "/parts"], ["POST", "/complete"]]) {
    const res = await t.call(m, `/v1/recordings/${start.body.id}${p}`, { auth, body: m === "POST" ? {} : undefined });
    assert.equal(res.status, 404, `${m} ${p}`);
  }
  assert.equal((await t.call("GET", "/v1/recordings", { auth })).body.recordings.length, 0);
});

test("a completion larger than stated that no longer fits is deleted", async () => {
  const t = setup({ quota: 11 * MiB });
  const start = await t.call("POST", "/v1/recordings", { body: { dataBytes: 2 * PART, metaBytes: 100, partSize: PART } });
  const parts = [];
  for (const { number, url } of start.body.partURLs) {
    const res = await t.storage.fetch(url, { method: "PUT", body: new Uint8Array(number === 2 ? PART + 2 * MiB : PART) });
    parts.push({ number, etag: res.headers.get("etag") });
  }
  await t.storage.fetch(start.body.metaURL, { method: "PUT", body: new Uint8Array(100) });
  const done = await t.call("POST", `/v1/recordings/${start.body.id}/complete`, { body: { parts } });
  assert.equal(done.status, 413);
  assert.equal(t.storage.bucket.objects.size, 0);
  assert.equal((await t.call("GET", "/v1/account")).body.usedBytes, 0);
});

test("completion without the details object is refused", async () => {
  const t = setup();
  const start = await t.call("POST", "/v1/recordings", { body: { dataBytes: PART, metaBytes: 100, partSize: PART } });
  const res = await t.storage.fetch(start.body.partURLs[0].url, { method: "PUT", body: new Uint8Array(PART) });
  const done = await t.call("POST", `/v1/recordings/${start.body.id}/complete`, { body: { parts: [{ number: 1, etag: res.headers.get("etag") }] } });
  assert.equal(done.status, 400);
  assert.equal((await t.call("GET", "/v1/account")).body.usedBytes, 0);
});

test("subscription states gate uploads and streaming", async () => {
  const t = setup();
  const { start } = await upload(t, PART);
  await t.call("POST", "/v1/dev/account", { body: { state: "ended", endedDaysAgo: 10 } });
  const account = (await t.call("GET", "/v1/account")).body;
  assert.equal(account.state, "grace");
  assert.equal(account.deleteAt, store.iso(t.now() + 20 * store.DAY));
  assert.equal((await t.call("POST", "/v1/recordings", { body: { dataBytes: PART, metaBytes: 1, partSize: PART } })).body.error, "no_subscription");
  assert.equal((await t.call("GET", `/v1/recordings/${start.body.id}/urls`)).status, 200);
  await t.call("POST", "/v1/dev/account", { body: { state: "none" } });
  assert.equal((await t.call("GET", `/v1/recordings/${start.body.id}/urls`)).status, 402);
});

test("cleanup aborts old uploads and deletes users after the grace period", async () => {
  const t = setup();
  await upload(t, PART);
  await upload(t, PART, { complete: false });
  t.advance(8 * store.DAY);
  let r = await cleanup(t.env, t.deps);
  assert.equal(r.abortedUploads, 1);
  assert.equal(t.storage.uploads.size, 0);
  assert.equal((await t.call("GET", "/v1/recordings")).body.recordings.length, 1);
  await t.call("POST", "/v1/dev/account", { body: { state: "ended", endedDaysAgo: 31 } });
  r = (await t.call("POST", "/v1/dev/cron", { body: {} })).body;
  assert.equal(r.deletedUsers, 1);
  assert.equal(t.storage.bucket.objects.size, 0);
  const account = (await t.call("GET", "/v1/account")).body;
  assert.equal(account.usedBytes, 0);
  assert.equal(account.state, "ended");
});

test("auth: no token, bad dev token, dev token disabled in production", async () => {
  const t = setup();
  assert.equal((await t.call("GET", "/v1/account", { auth: null })).status, 401);
  assert.equal((await t.call("GET", "/v1/account", { auth: "Dev wrong" })).status, 401);
  delete t.env.DEV_TOKEN;
  assert.equal((await t.call("GET", "/v1/account")).status, 401);
});

test("dev routes need the dev token", async () => {
  const t = setup();
  const { auth } = deviceKey();
  assert.equal((await t.call("POST", "/v1/dev/account", { auth, body: { state: "active" } })).status, 404);
  assert.equal((await t.call("POST", "/v1/dev/cron", { auth, body: {} })).status, 404);
});

test("App Store paths answer 503 while Apple is not configured", async () => {
  const t = setup();
  const res = await t.call("POST", "/v1/subscription", { auth: deviceKey().auth, body: { originalTransactionId: "1" } });
  assert.equal(res.status, 503);
  assert.equal(res.body.error, "apple_not_configured");
});

test("logs hold no URLs, keys or signatures", async () => {
  const t = setup();
  const lines = [];
  const original = console.log;
  console.log = (...a) => lines.push(a.join(" "));
  try {
    const { start } = await upload(t, PART + 5);
    await t.call("GET", `/v1/recordings/${start.body.id}/urls`);
    await t.call("DELETE", `/v1/recordings/${start.body.id}`);
  } finally { console.log = original; }
  assert.ok(lines.length >= 4);
  for (const line of lines) {
    assert.doesNotMatch(line, /https?:|X-Amz|Signature|devtoken/);
    const keys = Object.keys(JSON.parse(line));
    assert.ok(keys.every((k) => ["t", "route", "user", "rec", "bytes", "outcome", "error", "abortedUploads", "deletedUsers", "refreshed"].includes(k)), line);
  }
});

test("a key's first request registers the account, later ones reach it", async () => {
  const t = setup();
  const key = deviceKey();
  const first = await t.call("GET", "/v1/account", { auth: key.auth });
  assert.equal(first.status, 200);
  assert.equal(first.body.userId, key.accountId);
  assert.equal(first.body.state, "none");
  const row = await store.userByAccount(t.env.DB, key.accountId);
  assert.match(row.auth_hash, /^[0-9a-f]{64}$/);
  assert.ok(!row.auth_hash.includes(key.secret));
  assert.notEqual(row.id, key.accountId);
  const second = await t.call("GET", "/v1/recordings", { auth: key.auth });
  assert.equal(second.status, 200);
});

test("auth with a key: wrong secret, non-UUID id, uppercase id, short secret", async () => {
  const t = setup();
  const key = deviceKey();
  await t.call("GET", "/v1/account", { auth: key.auth });
  const other = deviceKey();
  assert.equal((await t.call("GET", "/v1/account", { auth: `Key ${key.accountId}:${other.secret}` })).status, 401);
  assert.equal((await t.call("GET", "/v1/account", { auth: `Key not-a-uuid:${key.secret}` })).status, 401);
  assert.equal((await t.call("GET", "/v1/account", { auth: `Key ${other.accountId.toUpperCase()}:${other.secret}` })).status, 401);
  assert.equal((await t.call("GET", "/v1/account", { auth: `Key ${other.accountId}:${b64urlEncode(new Uint8Array(16))}` })).status, 401);
  assert.equal((await t.call("GET", "/v1/account", { auth: `Bearer something` })).status, 401);
  assert.equal(await store.userByAccount(t.env.DB, other.accountId), null);
});

test("the subscription links by its app account token, never by the transaction id alone", async () => {
  const t = setup();
  Object.assign(t.env, await appStoreKey());
  const a = deviceKey(), b = deviceKey();
  for (const k of [a, b]) await t.call("GET", "/v1/account", { auth: k.auth });
  t.apple.set("1000000001", { appAccountToken: a.accountId.toUpperCase() });
  const linked = await t.call("POST", "/v1/subscription", { auth: a.auth, body: { originalTransactionId: "1000000001" } });
  assert.equal(linked.status, 200);
  assert.equal(linked.body.state, "active");
  // B knows the id, but the purchase was made for A.
  const foreign = await t.call("POST", "/v1/subscription", { auth: b.auth, body: { originalTransactionId: "1000000001" } });
  assert.equal(foreign.status, 409);
  assert.equal(foreign.body.error, "other_account");
  assert.equal((await t.call("GET", "/v1/account", { auth: b.auth })).body.state, "none");
  assert.equal((await t.call("GET", "/v1/account", { auth: a.auth })).body.state, "active");
  // A purchase without a token links only on a move.
  t.apple.set("1000000002", {});
  assert.equal((await t.call("POST", "/v1/subscription", { auth: b.auth, body: { originalTransactionId: "1000000002" } })).body.error, "other_account");
  assert.equal((await t.call("POST", "/v1/subscription", { auth: b.auth, body: { originalTransactionId: "1000000002", move: true } })).body.state, "active");
});

test("a move lasts until the token's account takes the subscription back", async () => {
  const t = setup();
  Object.assign(t.env, await appStoreKey());
  const a = deviceKey(), b = deviceKey();
  for (const k of [a, b]) await t.call("GET", "/v1/account", { auth: k.auth });
  t.apple.set("1000000003", { appAccountToken: a.accountId });
  await t.call("POST", "/v1/subscription", { auth: a.auth, body: { originalTransactionId: "1000000003" } });
  const moved = await t.call("POST", "/v1/subscription", { auth: b.auth, body: { originalTransactionId: "1000000003", move: true } });
  assert.equal(moved.body.state, "active");
  t.advance(1000);
  // A's next request of any kind takes it back; B is in grace from then on.
  assert.equal((await t.call("GET", "/v1/recordings", { auth: a.auth })).status, 200);
  assert.equal((await t.call("GET", "/v1/account", { auth: a.auth })).body.state, "active");
  const mover = (await t.call("GET", "/v1/account", { auth: b.auth })).body;
  assert.equal(mover.state, "grace");
  assert.equal(mover.deleteAt, store.iso(t.now() + 30 * store.DAY));
});

test("deleting the account removes its recordings; the same key starts empty and gets the subscription back", async () => {
  const t = setup();
  Object.assign(t.env, await appStoreKey());
  const a = deviceKey();
  await t.call("GET", "/v1/account", { auth: a.auth });
  t.apple.set("1000000004", { appAccountToken: a.accountId });
  await t.call("POST", "/v1/subscription", { auth: a.auth, body: { originalTransactionId: "1000000004" } });
  const call = t.call;
  t.call = (m, p, o = {}) => call(m, p, { auth: a.auth, ...o });
  await upload(t, PART + 1);
  await upload(t, PART + 2);
  await upload(t, PART + 3, { complete: false });
  t.call = call;
  assert.ok(t.storage.bucket.objects.size >= 4);
  assert.equal((await t.call("DELETE", "/v1/account", { auth: a.auth })).status, 204);
  assert.equal(t.storage.bucket.objects.size, 0);
  assert.equal(t.storage.uploads.size, 0);
  const again = await t.call("GET", "/v1/account", { auth: a.auth });
  assert.equal(again.body.usedBytes, 0);
  assert.equal(again.body.state, "active");
  assert.equal((await t.call("GET", "/v1/recordings", { auth: a.auth })).body.recordings.length, 0);
});

test("logs hold no account secret or Authorization header", async () => {
  const t = setup();
  Object.assign(t.env, await appStoreKey());
  const a = deviceKey();
  const lines = [];
  const original = console.log;
  console.log = (...x) => lines.push(x.join(" "));
  try {
    await t.call("GET", "/v1/account", { auth: a.auth });
    await t.call("GET", "/v1/account", { auth: `Key ${a.accountId}:${deviceKey().secret}` });
    t.apple.set("1000000005", { appAccountToken: crypto.randomUUID() });
    await t.call("POST", "/v1/subscription", { auth: a.auth, body: { originalTransactionId: "1000000005" } });
    await t.call("DELETE", "/v1/account", { auth: a.auth });
  } finally { console.log = original; }
  assert.ok(lines.length >= 3);
  for (const line of lines) {
    assert.ok(!line.includes(a.secret), line);
    assert.doesNotMatch(line, /Key |Authorization/);
  }
});
