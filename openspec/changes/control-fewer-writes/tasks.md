# Tasks

## 1. Worker

- [ ] 1.1 `authenticate()`: `used_at` only when older than a day (`AND used_at < ?`); test that two requests in a row write it once
- [ ] 1.2 Per-space minute limit through the `RATE_LIMIT` binding (120 per 60 s, keyed by space id); `counters` only for the hourly per-IP limits; fake binding in the tests, a test for 429 after 120 requests
- [ ] 1.3 `deploy.sh`: `ratelimit` binding in the script metadata; README (limits, what a poll writes); `node --test control-server/test/*.test.js`

## 2. Server

- [ ] 2.1 `flush`: send the status when it differs (without `lastContact` and `freeBytes`) from the last one sent, or after 5 minutes; `sync()` stops marking it dirty; comment on `ControlServerStatus`
- [ ] 2.2 Server tests: a quiet poll sends no status, a started recording sends one on the next poll, the heartbeat after 5 minutes; `scripts/vm.sh scripts/test.sh`

## 3. Verification and go-live

- [ ] 3.1 Dev deploy; a Fernsy Server container (`FERNSY_POLL=10`, `IPTV_CONTROL` dev) paired with Fernsy Dev on the demo server (`IPTV_SERVER` demo): idle for 30 minutes, then the D1 query statistics show no counter upserts, `used_at` once, about 6 status writes; a recording ordered from Fernsy Dev appears as running on the next poll
- [ ] 3.2 Prod deploy through a helper script the user runs; DEVELOPMENT.md; `openspec validate --all --strict`; archive, merge into `main`, push
