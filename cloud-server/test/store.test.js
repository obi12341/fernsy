import test from "node:test";
import assert from "node:assert/strict";
import { makeDB } from "./d1.js";
import * as store from "../store.js";

const now = Date.parse("2026-10-30T12:00:00Z");
const sub = (id, token, days = 1) => ({ originalTransactionId: id, productId: "p", expiresAt: store.iso(now + days * store.DAY), revokedAt: null, appAccountToken: token });

test("account states", () => {
  assert.equal(store.accountState(null, now).state, "none");
  assert.equal(store.accountState({ expires_at: store.iso(now + store.DAY) }, now).state, "active");
  const grace = store.accountState({ expires_at: store.iso(now - 10 * store.DAY) }, now);
  assert.equal(grace.state, "grace");
  assert.equal(grace.deleteAt, store.iso(now + 20 * store.DAY));
  assert.equal(store.accountState({ expires_at: store.iso(now - 31 * store.DAY) }, now).state, "ended");
  const refunded = store.accountState({ expires_at: store.iso(now + 20 * store.DAY), revoked_at: store.iso(now - store.DAY) }, now);
  assert.equal(refunded.state, "grace");
  assert.equal(refunded.endedAt, store.iso(now - store.DAY));
});

test("a user that lost its link is in grace from then on", () => {
  const lost = store.accountState({ expires_at: null, ended_at: store.iso(now - 5 * store.DAY) }, now);
  assert.equal(lost.state, "grace");
  assert.equal(lost.deleteAt, store.iso(now + 25 * store.DAY));
  assert.equal(store.accountState({ ended_at: store.iso(now - 31 * store.DAY) }, now).state, "ended");
  // A linked subscription decides over an old ended_at.
  assert.equal(store.accountState({ expires_at: store.iso(now + store.DAY), ended_at: store.iso(now - store.DAY) }, now).state, "active");
});

test("parallel starts cannot exceed the quota together", async () => {
  const db = makeDB();
  const user = await store.registerAccount(db, "acc-1", "h", now);
  const start = (id) => store.reserveRecording(db, { id, userId: user.id, dataBytes: 600, metaBytes: 10, partSize: 5242880, quota: 1000, now });
  const results = await Promise.all([start("a"), start("b"), start("c")]);
  assert.deepEqual(results.filter(Boolean).length, 1);
  assert.equal(await store.usedBytes(db, user.id), 610);
});

test("registration keeps the first hash and a stable user", async () => {
  const db = makeDB();
  const a = await store.registerAccount(db, "acc-1", "h1", now);
  const b = await store.registerAccount(db, "acc-1", "h2", now);
  assert.equal(a.id, b.id);
  assert.equal(b.auth_hash, "h1");
  assert.notEqual(a.id, "acc-1");
});

test("linking moves the subscription and ends the old holder's link", async () => {
  const db = makeDB();
  const a = await store.registerAccount(db, "acc-a", "h", now), b = await store.registerAccount(db, "acc-b", "h", now);
  assert.equal(await store.linkSubscription(db, a.id, sub("t1", "acc-a"), now), null);
  assert.equal(store.accountState(await store.userById(db, a.id), now).state, "active");
  assert.equal(await store.linkSubscription(db, b.id, sub("t1", "acc-a"), now), a.id);
  assert.equal(store.accountState(await store.userById(db, b.id), now).state, "active");
  const old = await store.userById(db, a.id);
  assert.equal(old.ended_at, store.iso(now));
  assert.equal(store.accountState(old, now).state, "grace");
});

test("take-back relinks to the account the purchase was made for", async () => {
  const db = makeDB();
  const a = await store.registerAccount(db, "acc-a", "h", now), b = await store.registerAccount(db, "acc-b", "h", now);
  await store.linkSubscription(db, b.id, sub("t1", "acc-a"), now);
  assert.deepEqual(await store.takeBack(db, b, now), []);
  assert.deepEqual(await store.takeBack(db, a, now), ["t1"]);
  assert.equal(store.accountState(await store.userById(db, a.id), now).state, "active");
  assert.equal(store.accountState(await store.userById(db, b.id), now).state, "grace");
});

test("deleting an account keeps its subscription for the next registration", async () => {
  const db = makeDB();
  const a = await store.registerAccount(db, "acc-a", "h", now);
  await store.linkSubscription(db, a.id, sub("t1", "acc-a"), now);
  await store.reserveRecording(db, { id: "r1", userId: a.id, dataBytes: 1, metaBytes: 1, partSize: 5242880, quota: 10, now });
  await store.deleteAccount(db, a.id);
  assert.equal(await store.userById(db, a.id), null);
  assert.equal((await store.subscription(db, "t1")).user_id, null);
  assert.equal(await store.usedBytes(db, a.id), 0);
  const again = await store.registerAccount(db, "acc-a", "h", now);
  assert.notEqual(again.id, a.id);
  assert.equal(store.accountState(again, now).state, "none");
  await store.takeBack(db, again, now);
  assert.equal(store.accountState(await store.userById(db, again.id), now).state, "active");
});

test("expired users and stale subscriptions on the new tables", async () => {
  const db = makeDB();
  const a = await store.registerAccount(db, "acc-a", "h", now), b = await store.registerAccount(db, "acc-b", "h", now);
  await store.linkSubscription(db, a.id, sub("t1", "acc-a", -40), now);
  await store.linkSubscription(db, b.id, sub("t2", "acc-b", -2), now);
  for (const [id, user] of [["r1", a], ["r2", b]]) {
    await store.reserveRecording(db, { id, userId: user.id, dataBytes: 1, metaBytes: 1, partSize: 5242880, quota: 10, now });
  }
  assert.deepEqual((await store.expiredUsersWithData(db, now, 30)).map((u) => u.id), [a.id]);
  assert.deepEqual((await store.staleSubscriptions(db, now)).map((s) => s.original_transaction_id), ["t2"]);
  const dev = await store.ensureDevUser(db, now);
  assert.equal(store.accountState(dev, now).state, "active");
  assert.deepEqual((await store.staleSubscriptions(db, now)).map((s) => s.original_transaction_id), ["t2"]);
});
