-- Fernsy Control D1 schema (headless-recorder design 3, 4). Applied by deploy.sh; statements are
-- idempotent so every deploy can run them.

CREATE TABLE IF NOT EXISTS spaces (
  id TEXT PRIMARY KEY,                      -- 32 hex chars, derived from the user's control key
  auth_hash TEXT NOT NULL,                  -- hex SHA-256 of the write secret
  change INTEGER NOT NULL DEFAULT 0,        -- last change number handed out
  created_at INTEGER NOT NULL,              -- ms since 1970
  used_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS items (
  space_id TEXT NOT NULL REFERENCES spaces(id),
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  data TEXT,                                -- base64 ciphertext; null for a deleted item (tombstone)
  change INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (space_id, kind, id)
);

CREATE INDEX IF NOT EXISTS items_change ON items(space_id, change);

CREATE TABLE IF NOT EXISTS pairing (
  mailbox TEXT PRIMARY KEY,                 -- the first four characters of the pairing code
  public_key TEXT NOT NULL,                 -- the server's X25519 key, base64
  tag TEXT NOT NULL,                        -- HMAC of the key under the code's secret part, base64
  claim_hash TEXT NOT NULL,                 -- hex SHA-256 of the server's claim secret
  message TEXT,                             -- the app's sealed message, base64
  message_tag TEXT,
  expires_at INTEGER NOT NULL
);

-- Request counters for limits: per space and minute, per hashed IP and hour.
CREATE TABLE IF NOT EXISTS counters (
  key TEXT PRIMARY KEY,                     -- "<what>:<space or ip hash>:<window>"
  n INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
