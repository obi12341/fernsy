# Design

## Context

- **What one poll writes today.** Fernsy Control (`control-server/worker.js`) authenticates every
  request in `authenticate()`, which does three things:
  - upserts a row in `counters` for the per-space minute limit;
  - reads the space;
  - updates `spaces.used_at`.

  A paired Fernsy Server polls every `FERNSY_POLL` seconds (default 30):
  - `GET /v1/items?since=` for new orders;
  - `PUT /v1/items/server/status`, its status, because `sync()` marks the status dirty on every
    poll.

  The PUT also bumps the space's change number and upserts the item (two rows with the index).
  In total that is about 7 written rows per poll.
- **The dev dashboard.** It showed this with a test container polling every 10 s: 16,588
  counter upserts, 16,638 `used_at` updates and 8,319 change bumps in 24 hours.
- **What the apps need.** `ControlServerStatus.isOnline` treats a server as offline after
  600 s without a report. The pairing check (`ServerModel`) waits for a report newer than the
  moment the code was sent.
- **How Cloudflare scales.** Workers scale out on their own: every request runs in an isolate
  in a data centre near the caller, with no instance count to set. D1 is one SQLite database
  with a single primary that applies writes one after another. So the database, not the worker,
  is what limits growth, and writes are what it pays for (rows written: 50 M a month in Workers
  Paid, then 1 $ per million; rows read: 25 B included).

## Goals / Non-Goals

**Goals:**
- A poll with nothing new writes nothing.
- A server costs about 26,000 written rows a month instead of 600,000.
- The apps still see changes on the next poll and the offline rule stays 10 minutes.

**Non-Goals:**
- Changing the poll interval.
- Changing the protocol between apps and server.
- Moving storage away from D1.
- The Fernsy Cloud worker.

## Decisions

### 1. Status on change, and every 5 minutes as a heartbeat
`flush` keeps the last status it sent. It sends a new one when the status without `lastContact`
and `freeBytes` differs from that, or when 5 minutes have passed since the last send. The first
report after start or pairing always goes out, because there is no previous one. `sync()` no
longer marks the status dirty; the places that change something the status shows (orders,
states, login outcome, errors) still do. Free space is only refreshed with the heartbeat. It
changes all the time while recording, and the apps show it as a rough figure.

Rejected:
- **Status on every poll** (today's behaviour): the cost this change removes.
- **A longer offline window in the apps:** it is not needed. A 5-minute heartbeat leaves room
  for one missed report within the 10 minutes.

### 2. `used_at` at most once a day
`UPDATE spaces SET used_at = ? WHERE id = ? AND used_at < ?`, with the bound one day earlier.
D1 does not count a row as written when the WHERE clause matches nothing.
The update runs after the answer through `ctx.waitUntil`, so it never adds to a request's
time; the answer does not depend on it. The daily cleanup
removes spaces idle for 90 days, so a day's precision does not change which spaces it keeps.

Rejected:
- **Dropping `used_at`:** the cleanup needs it.
- **Updating it only on writes:** a server that only reads for months would then look idle.
- **Workers KV instead of D1 (for the status or `used_at`):** it is not cheaper and it is not
  needed to avoid blocking. KV writes cost about five times a D1 row (5 $ vs 1 $ per million,
  1 M vs 50 M included). D1 is SQLite and holds no row or connection locks that would slow other
  requests: a write takes 0.2 ms at the median. The one write that the answer does not need goes
  through `waitUntil`.

### 3. Per-space minute limit through the Workers Rate Limiting binding
A `ratelimit` binding `RATE_LIMIT`, keyed by space id, with 120 requests per 60 s (the binding's
windows are 10 s or 60 s). `deploy.sh` adds it to the script metadata. The binding counts per
Cloudflare location and is eventually consistent. That is precise enough for a limit meant to
stop runaway clients, not to bill. The hourly per-IP limits for new spaces and pairing stay in
`counters`: they are only counted on those rare requests, and the binding has no hour window.
Tests use a fake binding with the same `limit({key})` shape.

Rejected:
- **Keeping the D1 counter:** it is one written row per request.
- **Counting in memory per isolate:** isolates come and go and run in many places, so the limit
  would mean nothing.
- **Durable Objects per space:** they are exact, but cost duration, and that is more than the
  limit is worth.

### 4. Stay on D1; no Redis, KV or sharding now
With decisions 1–3 a server writes about 8,600 status items (2–3 rows each) a month and reads
twice a minute. At 1,000 servers that is about 26 M written rows, within the included 50 M. The
writes come to about 3 per second, far below what one D1 primary handles.

Rejected:
- **Redis (Upstash or similar) for the online state:** Cloudflare has no Redis of its own, so it
  would be another external service and processor (privacy statement, account, outage). It is
  not cheaper for one small write every 5 minutes.
- **Workers KV for the status:** writes cost about five times D1's, and KV allows one write per
  second per key.
- **Durable Objects, or a D1 database per user:** they are worth it only when writes are much
  higher than these. Revisit if servers go into the tens of thousands.
- **D1 read replication:** reads are not the bottleneck.

## Risks / Trade-offs

- **Apps show a last contact up to 5 minutes old.** Accepted: the status text says "last
  contact", and every change still arrives on the next poll.
- **The rate limit is approximate per location.** Accepted for abuse protection. A client that
  hits several locations at once could exceed 120 a minute briefly.
- **Older servers keep writing their status every poll** until they update. The worker changes
  already remove four of the seven rows per poll for them.
- **Rate Limiting binding availability.** It is part of Workers Paid. Check in the dev deploy
  that the binding is accepted through the script upload API (metadata type `ratelimit`).
