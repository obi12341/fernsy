# Tasks

## 1. Tools

- [x] 1.1 Add `pause`, `resume` and `seek` (by_seconds, to_position, to_time, to_show_start, to_live; exactly one) and the live timeshift fields in `now_playing`; verify on the demo server (`IPTV_MCP=1 IPTV_MCPTOKEN=test`, live 101 buffered for 90 s): `now_playing` reports ~90 s rewindable and the buffer start time; seek −30 → behind live ~30 s; seek −600 → limited to the buffer start with `limited: true`; to_time 60 s ago; to_live → follows_live; pause → paused, after 10 s resume → still behind live by ~10 s more; film `movie:501` to_position 0:30 and by +10 — Done: after 90 s live: rewind 1:29, buffer 96 s, buffer start time, limit 60 min; −30 → 32 s behind; −600 → limited to the buffer start with the reason; to_live → follows live; to_time 60 s ago → 52 s behind live (live itself runs ~8 s behind real time); to_show_start before the buffer → limited; pause, 10 s, resume → 9 s behind; film to 0:30 and +10 → 0:40, to 5:00 → limited at the end 0:52. Fixed during the test: clock times now come from the buffer (`PlayerEngine.wallTime(of:)`), the published wall clock lagged after a seek
- [x] 1.2 Edge cases: seek with no or two targets → error; seek while nothing plays → error; a live channel without timeshift (`IPTV_TIMESHIFT=0` or the setting at its minimum if no switch exists) → "cannot be rewound"; document the tools in `DEVELOPMENT.md` — Done: no target, two targets, nothing playing, to_position on live and to_live on a film answer with errors; the "live without timeshift" branch cannot be produced (no switch, the minimum buffer is 2 min) and is checked by reading the code only; DEVELOPMENT.md updated

## 2. Integration

- [x] 2.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`
