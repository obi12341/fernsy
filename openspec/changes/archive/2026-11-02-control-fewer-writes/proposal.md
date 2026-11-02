# Proposal

## Why

Fernsy Control (the worker behind Fernsy Server) writes to its D1 database on every request,
even when nothing changed:

- each request bumps a rate-limit counter and the space's `used_at`;
- each server poll also rewrites the server's status item.

A server polling every 30 s therefore costs about 7 written rows per poll: roughly 173,000
requests and 600,000 written rows a month. The test container that polled every 10 s showed it
on the dashboard: 17,000 requests and about as many written rows in a day.

That breaks down as follows:
- **Price:** at 1,000 servers that is about 600 $ a month in D1 writes, roughly a fifth of each
  subscription's price.
- **Throughput:** the one D1 database serialises its writes, so around 10,000 servers it reaches
  its limit.

The Workers themselves scale out on their own. The writes are what does not.

## What Changes

- **Server status only when it changed:** The server writes its status item when something the
  apps show has changed (running and next recording, error, login, stream limit, version), and
  otherwise at most every 5 minutes as a sign of life with the last contact and free space. The
  apps' offline rule (10 minutes) stays.
- **`used_at` at most once a day:** The worker updates a space's `used_at` only when the stored
  value is older than a day. Idle spaces are removed after 90 days, so a day's precision is
  plenty.
- **Per-space rate limit without D1:** The limit of 120 requests per space and minute uses
  Cloudflare's Workers Rate Limiting binding instead of the `counters` table. The hourly limits
  for new spaces and pairing per IP stay in D1: they are counted only for those rare requests,
  and the binding knows only 10 s and 60 s windows.

Result: a poll that finds nothing new writes nothing, and a server costs about 26,000 written
rows a month instead of 600,000.

Out of scope:
- The poll interval (30 s stays; 60 s would halve the requests but delay new orders).
- Moving away from D1 (Durable Objects or a database per user), and D1 read replication. Not
  needed at these numbers; see design.
- The Fernsy Cloud worker (`cloud-server`), which counts its limits in D1 too, but only for
  uploads and assistant requests, not for a background poll.
- The apps' own polling while the server screen is open.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `headless-recorder`: "Server status" reports on change and at least every 5 minutes instead of
  on every poll; "Control service without an account" adds that a request with nothing new
  writes nothing.

## Impact

- `server/Sources/FernsyServer/Server.swift` (`flush`: write status only when changed or 5 minutes
  passed; `sync` no longer marks it dirty on every poll), the comment on `ControlServerStatus` in
  FernsyShared, server tests.
- `control-server/worker.js` (`authenticate`: conditional `used_at`, per-space limit through the
  `RATE_LIMIT` binding), `control-server/deploy.sh` (the binding in the script metadata),
  `control-server/test/*` (fake binding), `control-server/README.md`.
- Deploy: dev, then prod (prod deploy through a helper script the user runs).
- A new server build (`ghcr.io/obi12341/fernsy-server`) comes with the next release; older servers
  keep writing their status every poll, but already profit from the worker changes.
