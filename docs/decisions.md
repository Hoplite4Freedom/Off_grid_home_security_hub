# Decision Log

## Decided

| # | Decision | Choice | Rationale |
| - | -------- | ------ | --------- |
| 1 | Recording strategy | Motion-triggered only, 7-day motion / 10-day alert retention | Fits 8 TB pool with headroom; continuous recording unnecessary for this threat model |
| 2 | Storage layout | RAID 5 / ZFS RAIDZ1, 8 TB usable | Best balance of capacity and single-drive redundancy — see [storage.md](storage.md) |
| 3 | Remote access | **Tailscale** (decided 2026-07-24) | Zero port forwarding, WireGuard-based, MFA via identity provider, MagicDNS for friendly hostnames, free tier covers this deployment. Simpler than Cloudflare Tunnel for a private single-household hub with no public endpoints — see [remote-access.md](remote-access.md) |
| 4 | Container platform | Docker Compose | Single-node deployment; Kubernetes is overkill |
| 5 | MQTT broker | Eclipse Mosquitto 2.x, password auth, no anonymous access | Lightweight, the de-facto standard for Frigate + Home Assistant |

## Pending

| # | Question | Blocking | Notes |
| - | -------- | -------- | ----- |
| 1 | PTZ camera brand/model selection | Phase 1 | Must meet criteria in [hardware.md](hardware.md); affects per-camera config entries only |
| 2 | Physical door/window sensors vs. camera-based AI | Phase 5 | Zigbee (Aqara/Sonoff) at $15–30/sensor vs. zero-hardware camera zones |
| 3 | PoE switch capacity (24-port vs. 16-port) | Phase 1 | Driven by final camera count; 24-port recommended if expanding to 20 |
| 4 | Offsite backup provider (Backblaze B2 vs. Wasabi vs. USB rotation) | Phase 6 | ~$5–10/month for cloud options |
| 5 | Motion tracking sensitivity thresholds | Phase 3 | Requires on-site tuning after 2 weeks of baseline data |
| 6 | Home Assistant integration depth (locks, voice, geofencing) | Phase 5 | Start with notifications + chain activation |
| 7 | Storage expansion budget (current allocation ~$650–950) | Phase 4 | Revisit after Phase 1 real-world write rates |
