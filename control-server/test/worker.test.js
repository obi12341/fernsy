import test from "node:test";
import assert from "node:assert/strict";
import { makeDB } from "./d1.js";
import { handle, cleanup, LIMITS } from "../worker.js";

const DAY = 86_400_000;
const b64 = (bytes) => Buffer.from(bytes).toString("base64");
const b64url = (bytes) => Buffer.from(bytes).toString("base64url");
const random = (n) => crypto.getRandomValues(new Uint8Array(n));
const sha256Hex = async (text) => Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))).toString("hex");

/// A space key as the apps derive it from the control key.
function spaceKey() {
  const id = Buffer.from(random(16)).toString("hex");
  return `Space ${id}:${b64url(random(32))}`;
}

function setup() {
  let now = Date.parse("2026-11-01T12:00:00Z");
  const env = { DB: makeDB() };
  const call = async (method, path, { body, auth, ip = "192.0.2.1" } = {}) => {
    const headers = { "CF-Connecting-IP": ip };
    if (auth) headers.Authorization = auth;
    const res = await handle(new Request("https://control.test" + path, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, { now: () => now });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  return { env, call, advance: (ms) => { now += ms; }, now: () => now };
}

test("items: write, list since a change, delete as tombstone", async () => {
  const t = setup();
  const auth = spaceKey();
  const data = b64(random(100));
  assert.deepEqual((await t.call("GET", "/v1/items", { auth })).body, { items: [], change: 0, more: false });
  assert.equal((await t.call("PUT", "/v1/items/order/o1", { auth, body: { data } })).body.change, 1);
  assert.equal((await t.call("PUT", "/v1/items/state/o1", { auth, body: { data } })).body.change, 2);
  let list = (await t.call("GET", "/v1/items?since=1", { auth })).body;
  assert.equal(list.change, 2);
  assert.deepEqual(list.items.map((i) => [i.kind, i.id, i.data]), [["state", "o1", data]]);
  assert.equal((await t.call("DELETE", "/v1/items/order/o1", { auth })).body.change, 3);
  list = (await t.call("GET", "/v1/items?since=2", { auth })).body;
  assert.deepEqual(list.items.map((i) => [i.kind, i.id, i.deleted, i.data]), [["order", "o1", true, undefined]]);
  // Deleting again changes nothing; writing it again brings it back.
  assert.equal((await t.call("DELETE", "/v1/items/order/o1", { auth })).body.change, 3);
  assert.equal((await t.call("PUT", "/v1/items/order/o1", { auth, body: { data } })).body.change, 4);
});

test("spaces are separate and guarded by their write secret", async () => {
  const t = setup();
  const a = spaceKey();
  await t.call("PUT", "/v1/items/order/o1", { auth: a, body: { data: b64(random(10)) } });
  const b = spaceKey();
  assert.deepEqual((await t.call("GET", "/v1/items", { auth: b })).body.items, []);
  const wrong = a.replace(/:.*/, ":" + b64url(random(32)));
  assert.equal((await t.call("GET", "/v1/items", { auth: wrong })).status, 401);
  assert.equal((await t.call("GET", "/v1/items")).status, 401);
  assert.equal((await t.call("GET", "/v1/items", { auth: "Space abc:def" })).status, 401);
});

test("limits: item size, item count, requests per minute, new spaces per IP", async () => {
  const t = setup();
  const auth = spaceKey();
  assert.equal((await t.call("PUT", "/v1/items/order/big", { auth, body: { data: b64(random(LIMITS.itemBytes + 1)) } })).status, 413);
  assert.equal((await t.call("PUT", "/v1/items/order/x", { auth, body: { data: "not base64!" } })).status, 400);
  assert.equal((await t.call("PUT", "/v1/items/Order/x", { auth, body: { data: "AA==" } })).status, 400);
  await t.call("GET", "/v1/items", { auth });   // registers the space
  for (let i = 0; i < LIMITS.items; i++) {
    t.env.DB.raw.prepare("INSERT INTO items (space_id, kind, id, data, change, updated_at) VALUES (?, 'order', ?, 'AA==', 0, 0)")
      .run(auth.slice(6, 38), `o${i}`);
  }
  assert.equal((await t.call("PUT", "/v1/items/order/one-more", { auth, body: { data: "AA==" } })).body.error, "full");
  // Replacing an existing item is still fine.
  assert.equal((await t.call("PUT", "/v1/items/order/o1", { auth, body: { data: "AQ==" } })).status, 200);

  t.advance(60_000);
  let last;
  for (let i = 0; i < LIMITS.perMinute + 1; i++) last = await t.call("GET", "/v1/items", { auth });
  assert.equal(last.status, 429);
  t.advance(60_000);
  assert.equal((await t.call("GET", "/v1/items", { auth })).status, 200);

  const results = [];
  for (let i = 0; i < LIMITS.newSpacesPerHour + 1; i++) results.push((await t.call("GET", "/v1/items", { auth: spaceKey(), ip: "198.51.100.7" })).status);
  assert.equal(results.at(-1), 429);
  assert.equal((await t.call("GET", "/v1/items", { auth: spaceKey(), ip: "198.51.100.8" })).status, 200);
});

test("listing pages through more than a page of changes", async () => {
  const t = setup();
  const auth = spaceKey();
  const id = auth.slice(6, 38);
  await t.call("GET", "/v1/items", { auth });   // registers the space
  for (let i = 1; i <= LIMITS.items + 5; i++) {
    t.env.DB.raw.prepare("INSERT INTO items (space_id, kind, id, data, change, updated_at) VALUES (?, 'state', ?, NULL, ?, 0)").run(id, `s${i}`, i);
  }
  t.env.DB.raw.prepare("UPDATE spaces SET change = ? WHERE id = ?").run(LIMITS.items + 5, id);
  const first = (await t.call("GET", "/v1/items", { auth })).body;
  assert.equal(first.more, true);
  assert.equal(first.items.length, LIMITS.items);
  const second = (await t.call("GET", `/v1/items?since=${first.change}`, { auth })).body;
  assert.equal(second.more, false);
  assert.equal(second.items.length, 5);
  assert.equal(second.change, LIMITS.items + 5);
});

test("deleting a space removes its items", async () => {
  const t = setup();
  const auth = spaceKey();
  await t.call("PUT", "/v1/items/order/o1", { auth, body: { data: "AA==" } });
  assert.equal((await t.call("DELETE", "/v1/space", { auth })).status, 204);
  assert.deepEqual((await t.call("GET", "/v1/items", { auth })).body, { items: [], change: 0, more: false });
});

test("pairing: server opens, app reads and answers once, server claims and the mailbox closes", async () => {
  const t = setup();
  const claim = b64url(random(32));
  const publicKey = b64(random(32)), tag = b64(random(32));
  const open = await t.call("POST", "/v1/pairing/7K3Q", { body: { publicKey, tag, claimHash: await sha256Hex(claim) } });
  assert.equal(open.status, 200);
  assert.equal((await t.call("POST", "/v1/pairing/7K3Q", { body: { publicKey, tag, claimHash: await sha256Hex(claim) } })).body.error, "taken");
  assert.deepEqual((await t.call("GET", "/v1/pairing/7K3Q")).body, { publicKey, tag, expiresAt: open.body.expiresAt });

  // Nothing yet; only the server's claim may ask.
  assert.equal((await t.call("GET", "/v1/pairing/7K3Q/message")).status, 401);
  assert.deepEqual((await t.call("GET", "/v1/pairing/7K3Q/message", { auth: `Claim ${claim}` })).body, { message: null });

  const message = b64(random(300)), messageTag = b64(random(32));
  assert.equal((await t.call("PUT", "/v1/pairing/7K3Q/message", { body: { message, tag: messageTag } })).status, 204);
  assert.equal((await t.call("PUT", "/v1/pairing/7K3Q/message", { body: { message, tag: messageTag } })).body.error, "taken");
  assert.deepEqual((await t.call("GET", "/v1/pairing/7K3Q/message", { auth: `Claim ${claim}` })).body, { message, tag: messageTag });
  assert.equal((await t.call("GET", "/v1/pairing/7K3Q")).status, 404);
});

test("pairing: codes expire, are well-formed and limited per IP", async () => {
  const t = setup();
  const body = { publicKey: b64(random(32)), tag: b64(random(32)), claimHash: await sha256Hex("x") };
  assert.equal((await t.call("POST", "/v1/pairing/ABCD", { body })).status, 200);
  t.advance(LIMITS.pairingMinutes * 60_000);
  assert.equal((await t.call("GET", "/v1/pairing/ABCD")).status, 404);
  // An expired mailbox can be opened again.
  assert.equal((await t.call("POST", "/v1/pairing/ABCD", { body })).status, 200);
  assert.equal((await t.call("GET", "/v1/pairing/ABCI")).status, 400);   // I is not Crockford base32
  assert.equal((await t.call("POST", "/v1/pairing/WXYZ", { body: { ...body, publicKey: b64(random(31)) } })).status, 400);

  let last;
  for (let i = 0; i < LIMITS.pairingPerHour + 1; i++) last = await t.call("GET", "/v1/pairing/ZZZZ", { ip: "203.0.113.9" });
  assert.equal(last.status, 429);
});

test("cleanup: mailboxes, counters, old tombstones and idle spaces", async () => {
  const t = setup();
  const active = spaceKey(), idle = spaceKey();
  await t.call("PUT", "/v1/items/order/o1", { auth: idle, body: { data: "AA==" } });
  await t.call("PUT", "/v1/items/order/o1", { auth: active, body: { data: "AA==" } });
  await t.call("DELETE", "/v1/items/order/o1", { auth: active });
  await t.call("POST", "/v1/pairing/ABCD", { body: { publicKey: b64(random(32)), tag: b64(random(32)), claimHash: await sha256Hex("x") } });
  t.advance(LIMITS.tombstoneDays * DAY);
  await t.call("PUT", "/v1/items/order/o2", { auth: active, body: { data: "AA==" } });
  let result = await cleanup(t.env, { now: t.now });
  assert.equal(result.pairing, 1);
  assert.equal(result.tombstones, 1);
  assert.equal(result.idleSpaces, 0);
  t.advance((LIMITS.idleSpaceDays - LIMITS.tombstoneDays) * DAY);
  result = await cleanup(t.env, { now: t.now });
  assert.equal(result.idleSpaces, 1);
  assert.equal(result.idleItems, 1);
  assert.equal((await t.call("GET", "/v1/items", { auth: active })).body.items.length, 1);
});
