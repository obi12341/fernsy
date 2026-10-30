// D1 access for Fernsy Cloud (cloud-server design E): users from the cloud key, their
// subscriptions linked by Apple's appAccountToken (cloud-account-from-icloud-key design B, C, E),
// recordings with quota accounting. `db` is a D1 binding (or the test stand-in with the same
// prepare/bind/first/all/run API). Times are ISO-8601 UTC strings.

export const DAY = 86400000;

export function iso(ms) { return ms == null ? null : new Date(ms).toISOString(); }

/// The subscription state the apps see (recording-cloud "Subscription end"). `user` is a row
/// of `userById`: the user joined with its linked subscription (`expires_at`, `revoked_at`),
/// plus `ended_at` from losing a link. A linked subscription decides; without one, `ended_at`
/// starts the grace period.
export function accountState(user, now, graceDays = 30) {
  let expires = null, ended = null;
  if (user && user.expires_at) {
    expires = Date.parse(user.expires_at);
    const revoked = user.revoked_at ? Date.parse(user.revoked_at) : null;
    ended = revoked != null ? Math.min(revoked, expires) : (expires <= now ? expires : null);
    if (ended == null) return { state: "active", expiresAt: iso(expires), endedAt: null, deleteAt: null };
  } else if (user && user.ended_at) {
    ended = Date.parse(user.ended_at);
  } else {
    return { state: "none", expiresAt: null, endedAt: null, deleteAt: null };
  }
  const deleteAt = ended + graceDays * DAY;
  return { state: now < deleteAt ? "grace" : "ended", expiresAt: iso(expires), endedAt: iso(ended), deleteAt: iso(deleteAt) };
}

// The user with its linked subscription (the one with the latest expiry, if several).
const USER_WITH_SUBSCRIPTION = `SELECT u.*, s.original_transaction_id, s.product_id, s.expires_at, s.revoked_at
  FROM users u LEFT JOIN subscriptions s ON s.original_transaction_id = (
    SELECT original_transaction_id FROM subscriptions WHERE user_id = u.id ORDER BY expires_at DESC LIMIT 1)`;

export async function userById(db, id) {
  return db.prepare(`${USER_WITH_SUBSCRIPTION} WHERE u.id = ?`).bind(id).first();
}

export async function userByAccount(db, accountId) {
  return db.prepare(`${USER_WITH_SUBSCRIPTION} WHERE u.account_id = ?`).bind(accountId).first();
}

/// The user for an account id, registered with `authHash` on first use (design B). The caller
/// compares the stored hash: a known id keeps the hash it was registered with.
export async function registerAccount(db, accountId, authHash, now) {
  const found = await userByAccount(db, accountId);
  if (found) return found;
  await db.prepare("INSERT OR IGNORE INTO users (id, account_id, auth_hash, created_at) VALUES (?, ?, ?, ?)")
    .bind(crypto.randomUUID(), accountId, authHash, iso(now)).run();
  return userByAccount(db, accountId);
}

/// The dev user (`Authorization: Dev`), with a stand-in subscription that starts active;
/// /v1/dev/account changes it later.
export async function ensureDevUser(db, now) {
  let user = await userByAccount(db, "dev");
  if (user) return user;
  await db.prepare("INSERT OR IGNORE INTO users (id, account_id, auth_hash, created_at) VALUES (?, 'dev', '-', ?)")
    .bind(crypto.randomUUID(), iso(now)).run();
  user = await userByAccount(db, "dev");
  await db.prepare("INSERT OR IGNORE INTO subscriptions (original_transaction_id, user_id, product_id, expires_at) VALUES (?, ?, 'dev', ?)")
    .bind(`dev:${user.id}`, user.id, iso(now + 3650 * DAY)).run();
  return userByAccount(db, "dev");
}

export async function subscription(db, originalTransactionId) {
  return db.prepare("SELECT * FROM subscriptions WHERE original_transaction_id = ?").bind(originalTransactionId).first();
}

/// Links a subscription to the user, with Apple's status (design C, E). The user that held
/// it before, if another one, loses the link and enters its grace period. Returns that
/// user's id or null.
export async function linkSubscription(db, userId, { originalTransactionId, productId, expiresAt, revokedAt, appAccountToken }, now) {
  const before = await subscription(db, originalTransactionId);
  const previous = before && before.user_id && before.user_id !== userId ? before.user_id : null;
  await db.prepare(
    `INSERT INTO subscriptions (original_transaction_id, token_account_id, user_id, product_id, expires_at, revoked_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(original_transaction_id) DO UPDATE SET token_account_id = excluded.token_account_id,
       user_id = excluded.user_id, product_id = excluded.product_id, expires_at = excluded.expires_at, revoked_at = excluded.revoked_at`)
    .bind(originalTransactionId, appAccountToken ?? null, userId, productId, expiresAt, revokedAt).run();
  await db.prepare("UPDATE users SET ended_at = NULL WHERE id = ?").bind(userId).run();
  if (previous) await endLink(db, previous, now);
  return previous;
}

/// A user that lost its subscription link: grace starts now, unless it still has another one.
async function endLink(db, userId, now) {
  const other = await db.prepare("SELECT 1 FROM subscriptions WHERE user_id = ? LIMIT 1").bind(userId).first();
  if (!other) await db.prepare("UPDATE users SET ended_at = ? WHERE id = ?").bind(iso(now), userId).run();
}

/// Subscriptions bought for this account but linked elsewhere (or nowhere): the take-back
/// of design E. Returns the original transaction ids that were relinked.
export async function takeBack(db, user, now) {
  const { results } = await db.prepare(
    "SELECT * FROM subscriptions WHERE token_account_id = ? AND (user_id IS NULL OR user_id != ?)")
    .bind(user.account_id, user.id).all();
  for (const s of results) {
    await linkSubscription(db, user.id, {
      originalTransactionId: s.original_transaction_id, productId: s.product_id, expiresAt: s.expires_at,
      revokedAt: s.revoked_at, appAccountToken: s.token_account_id,
    }, now);
  }
  return results.map((s) => s.original_transaction_id);
}

/// Apple's latest word on a known subscription (notifications, cron, account refresh).
export async function updateSubscription(db, originalTransactionId, { productId, expiresAt, revokedAt, appAccountToken }) {
  await db.prepare(
    `UPDATE subscriptions SET product_id = ?, expires_at = ?, revoked_at = ?, token_account_id = COALESCE(?, token_account_id)
     WHERE original_transaction_id = ?`)
    .bind(productId, expiresAt, revokedAt, appAccountToken ?? null, originalTransactionId).run();
}

export async function setDevState(db, userId, { expiresAt, revokedAt = null, quotaBytes }) {
  await db.prepare("UPDATE subscriptions SET expires_at = ?, revoked_at = ? WHERE original_transaction_id = ?")
    .bind(expiresAt, revokedAt, `dev:${userId}`).run();
  await db.prepare("UPDATE users SET quota_bytes = ?, ended_at = NULL WHERE id = ?").bind(quotaBytes ?? null, userId).run();
}

/// Removes the account row (design G). Its subscriptions stay, unlinked, so the next
/// registration of the same key takes them back; the dev user's stand-in goes with it.
/// The caller deletes the recordings' objects first.
export async function deleteAccount(db, userId) {
  await db.prepare("DELETE FROM subscriptions WHERE original_transaction_id = ?").bind(`dev:${userId}`).run();
  await db.prepare("UPDATE subscriptions SET user_id = NULL WHERE user_id = ?").bind(userId).run();
  await db.prepare("DELETE FROM recordings WHERE user_id = ?").bind(userId).run();
  await db.prepare("DELETE FROM users WHERE id = ?").bind(userId).run();
}

/// Bytes counted against the quota: finished recordings plus the stated sizes of uploads.
export async function usedBytes(db, userId) {
  const row = await db.prepare("SELECT COALESCE(SUM(data_bytes + meta_bytes), 0) AS used FROM recordings WHERE user_id = ?")
    .bind(userId).first();
  return Number(row.used);
}

/// Reserves an upload in one statement, so parallel starts cannot exceed the quota together.
/// Returns false when it does not fit.
export async function reserveRecording(db, { id, userId, dataBytes, metaBytes, partSize, quota, now }) {
  const result = await db.prepare(
    `INSERT INTO recordings (id, user_id, data_bytes, meta_bytes, part_size, state, created_at)
     SELECT ?, ?, ?, ?, ?, 'uploading', ?
     WHERE (SELECT COALESCE(SUM(data_bytes + meta_bytes), 0) FROM recordings WHERE user_id = ?) + ? <= ?`)
    .bind(id, userId, dataBytes, metaBytes, partSize, iso(now), userId, dataBytes + metaBytes, quota).run();
  return result.meta.changes === 1;
}

export async function setUploadId(db, id, uploadId) {
  await db.prepare("UPDATE recordings SET upload_id = ? WHERE id = ?").bind(uploadId, id).run();
}

export async function recording(db, userId, id) {
  return db.prepare("SELECT * FROM recordings WHERE id = ? AND user_id = ?").bind(id, userId).first();
}

export async function completeRecording(db, id, { dataBytes, metaBytes, now }) {
  await db.prepare("UPDATE recordings SET state = 'done', upload_id = NULL, data_bytes = ?, meta_bytes = ?, completed_at = ? WHERE id = ?")
    .bind(dataBytes, metaBytes, iso(now), id).run();
}

export async function deleteRecordingRow(db, id) {
  await db.prepare("DELETE FROM recordings WHERE id = ?").bind(id).run();
}

export async function doneRecordings(db, userId) {
  const { results } = await db.prepare(
    "SELECT id, data_bytes, meta_bytes, completed_at FROM recordings WHERE user_id = ? AND state = 'done' ORDER BY completed_at DESC")
    .bind(userId).all();
  return results;
}

/// Uploads started before `before` and never completed.
export async function abandonedUploads(db, before) {
  const { results } = await db.prepare("SELECT * FROM recordings WHERE state = 'uploading' AND created_at < ?").bind(iso(before)).all();
  return results;
}

/// Users whose grace period is over and who still have recordings.
export async function expiredUsersWithData(db, now, graceDays) {
  const { results } = await db.prepare("SELECT DISTINCT user_id FROM recordings").all();
  const users = [];
  for (const { user_id } of results) {
    const user = await userById(db, user_id);
    if (user && accountState(user, now, graceDays).state === "ended") users.push(user);
  }
  return users;
}

export async function recordingsOf(db, userId) {
  const { results } = await db.prepare("SELECT * FROM recordings WHERE user_id = ?").bind(userId).all();
  return results;
}

/// Subscriptions whose expiry passed without a word from Apple (refreshed by the cron job).
export async function staleSubscriptions(db, now, limit = 50) {
  const { results } = await db.prepare(
    `SELECT * FROM subscriptions WHERE original_transaction_id NOT LIKE 'dev:%' AND revoked_at IS NULL
     AND expires_at < ? AND expires_at > ? LIMIT ?`).bind(iso(now), iso(now - 35 * DAY), limit).all();
  return results;
}
