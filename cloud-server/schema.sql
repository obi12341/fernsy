-- Fernsy Cloud D1 schema (cloud-server design E; accounts from cloud-account-from-icloud-key
-- design A–C). Applied by deploy.sh; statements are idempotent so every deploy can run them.

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,                      -- random UUID, the user id in object keys
  account_id TEXT NOT NULL UNIQUE,          -- derived from the cloud key (lowercase UUID); 'dev' for the dev user
  auth_hash TEXT NOT NULL,                  -- hex SHA-256 of the access secret
  created_at TEXT NOT NULL,
  ended_at TEXT,                            -- set when the user lost its subscription link (grace starts)
  quota_bytes INTEGER                       -- null: the worker's QUOTA_BYTES
);

CREATE TABLE IF NOT EXISTS subscriptions (
  original_transaction_id TEXT PRIMARY KEY, -- 'dev:<userId>' for the dev user's stand-in
  token_account_id TEXT,                    -- Apple's appAccountToken; null when the purchase has none
  user_id TEXT,                             -- the user it is linked to now
  product_id TEXT,
  expires_at TEXT,                          -- subscription expiry from Apple
  revoked_at TEXT                           -- refund or revocation from Apple
);

CREATE INDEX IF NOT EXISTS subscriptions_token ON subscriptions(token_account_id);
CREATE INDEX IF NOT EXISTS subscriptions_user ON subscriptions(user_id);

CREATE TABLE IF NOT EXISTS recordings (
  id TEXT PRIMARY KEY,                      -- random UUID
  user_id TEXT NOT NULL REFERENCES users(id),
  data_bytes INTEGER NOT NULL,              -- stated at start, actual after completion
  meta_bytes INTEGER NOT NULL,
  part_size INTEGER NOT NULL,
  state TEXT NOT NULL,                      -- 'uploading' | 'done'
  upload_id TEXT,                           -- R2 multipart upload id while uploading
  created_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS recordings_user ON recordings(user_id, state);
