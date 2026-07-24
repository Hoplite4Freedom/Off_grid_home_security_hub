# Path to Completion

This document turns the planning summary in [`../README.md`](../README.md) and the findings in
[`REVIEW.md`](./REVIEW.md) into an ordered plan with concrete deliverables and exit criteria.

Milestones are ordered by dependency, not by calendar. Each one lists what lands in the repository
and what has to be demonstrably true before the next milestone starts. Nothing here estimates
duration; the sequencing is what matters, because several milestones are gated on hardware
purchases that the earlier milestones exist to de-risk.

## Current state

- One file: a planning session summary. No configuration, code, scripts, or tests.
- No hardware purchased or validated (as far as the repository records).
- Nine open questions are listed at the end of the README, several of which block purchasing.
- Three of those questions can be closed immediately from the review; see the decision log below.

## Target end state

A repository that can rebuild the entire hub from bare hardware: a validated Frigate configuration,
a Compose stack, Home Assistant automations, a documented network and power design, monitoring, a
tested backup and restore procedure, and runbooks for the failure modes that actually occur.

---

## Milestone 0 — Make the repository a repository

Purely local work with no hardware dependency, and it unblocks everything else.

**Deliverables**

- `.gitignore` covering `.env`, `secrets/`, `*.key`, `*.pem`, and any `config.local.*`.
- `.env.example` listing every required variable with placeholder values.
- `LICENSE`.
- Directory skeleton:

```
docs/            design, decisions, runbooks
compose/         docker-compose.yml and env templates
frigate/         config.yml plus per-camera includes
homeassistant/   automations, scripts, packages
scripts/         bootstrap, backup, health checks
network/         VLAN plan, IP inventory, switch config notes
power/           load budget, generation and battery sizing
.github/         CI workflows
```

- `docs/SPEC.md`: the settled specification, split out from the session summary per finding L2.
  The README stays as the historical planning record.
- `docs/DECISIONS.md`: one entry per decision with status, the options considered, and the reason.
  Seeded from the decision log at the end of this document.

**Exit criteria** — a stranger can clone the repository and understand what is being built, what is
decided, and what is still open, without reading a chat transcript.

---

## Milestone 1 — Close the blocking decisions

Purchasing cannot start while the camera type, camera count, and power architecture are open,
because those three determine each other. Camera choice sets the power draw; the power budget caps
the camera count; the camera count sets the Coral and switch sizing.

**Deliverables**

- `power/load-budget.md`: a per-device table of continuous and peak draw for the *chosen* camera
  mix, totalled to a daily kWh figure. This is the input to every other power number.
- `power/sizing.md`: solar array sizing at both annual-average and winter-worst-case peak-sun-hours
  for the actual site latitude, battery bank sizing at a stated autonomy target, and the resulting
  bill of materials with costs.
- A revised cost summary that includes the power subsystem, cabling, mounts, UPS, surge protection,
  and enclosure — the items missing per finding M7.
- `docs/DECISIONS.md` updated: camera mix (fixed versus PTZ), remote access method, storage layout,
  and backup target all moved from open to decided.

**Exit criteria** — a single number for continuous load, a single number for daily energy, and a
total project cost that includes generation and storage. If that total is unacceptable, the
mitigations below are applied and the loop repeats *before* anything is ordered.

**Load-reduction levers, in rough order of effectiveness**

1. Fixed cameras for most positions, PTZ only where autotracking earns its cost (finding H1). This
   removes both motor draw and IR-heater draw across most of the fleet.
2. Disable camera IR heaters, or put them on a temperature-gated circuit rather than always-on.
3. DC-native distribution: run the ZimaBoard and switch from the battery bank at 12/24 V rather
   than inverting to AC and back down, which removes two conversion stages.
4. Duty-cycle low-activity cameras — schedule or PIR-trigger rather than 24/7 streaming.
5. Reduce camera count for the first build and expand only if the measured power headroom allows,
   mirroring the phased-rollout logic already in the plan.

---

## Milestone 2 — Validated configuration, before hardware arrives

Everything here can be written and CI-validated against a Frigate container with zero cameras
attached, which is why it comes before the build.

**Deliverables**

- `frigate/config.yml` on the current Frigate schema, correcting finding C3. The PTZ block becomes
  per-camera:

```yaml
cameras:
  driveway:
    onvif:
      host: 10.20.0.11
      port: 8000
      user: "{FRIGATE_ONVIF_USER}"
      password: "{FRIGATE_ONVIF_PASSWORD}"
      autotracking:
        enabled: true
        calibrate_on_startup: true   # set false once movement_weights are generated
        zooming: relative
        zoom_factor: 0.3
        track:
          - person
          - car
        required_zones:
          - driveway_approach
        return_preset: home
        timeout: 30
```

  and retention uses the current keys:

```yaml
record:
  enabled: true
  retain:
    days: 7
    mode: motion
  alerts:
    retain:
      days: 10
      mode: motion
  detections:
    retain:
      days: 10
      mode: motion
```

- Hardware acceleration and restreaming wired in, per findings M1 and M2: `hwaccel_args` using the
  appropriate `preset-intel-qsv-*` preset, `/dev/dri` passed into the container, and every camera
  pulled once through `go2rtc` with Frigate consuming the local restream.
- `compose/docker-compose.yml` with Frigate, go2rtc (bundled), an MQTT broker, and Home Assistant.
  `shm_size` and the `/tmp/cache` tmpfs sized from Frigate's documented formula for the chosen
  camera count and detect resolution (finding M4). Docker's data root and Frigate's database
  relocated off the eMMC onto the NVMe (finding M3).
- All credentials referenced as `FRIGATE_`-prefixed environment variables or Docker secrets, never
  literals (finding H4).
- `network/vlan-plan.md` and `network/ip-inventory.md`: camera VLAN, management VLAN, IoT VLAN,
  static assignments per camera, and an explicit default-deny egress rule for the camera VLAN so
  cameras cannot reach the internet. Includes the local NTP source for the camera VLAN (finding M5).
- `.github/workflows/validate.yml`: `yamllint` over the repository plus Frigate's built-in config
  validation run against `frigate/config.yml` in the official container.

**Exit criteria** — CI is green, and `docker compose config` plus Frigate's config validator both
pass against the committed files with only placeholder credentials.

---

## Milestone 3 — Bench build

Assemble and burn in on mains power at a bench before anything is mounted outdoors or connected to
a battery bank. This exists to catch the hardware unknowns in findings C2 and H2 while returns are
still possible.

**Deliverables**

- `docs/runbooks/bootstrap.md` plus `scripts/bootstrap.sh`: base OS install, filesystem layout,
  Docker installation, mount points, and stack bring-up, written as the procedure is executed.
- Storage built to the tiered layout from finding C2 — NVMe as hot tier, the SATA pair mirrored or
  synced as archive — with the actual chosen layout recorded in `docs/DECISIONS.md`.
- Two to three cameras running end to end: detection, recording, retention, and one autotracking
  camera with calibration completed and `movement_weights` committed.
- `docs/measurements.md`: measured inference time per Coral, detection FPS, CPU load, package power
  at the wall, and observed daily write volume extrapolated to the full camera count.

**Exit criteria**

- Inference time is in the expected ~10 ms range and neither Coral drops off the USB bus during a
  72-hour soak (finding H2).
- Hardware decode is confirmed active — CPU stays low with all streams running.
- Measured power draw is within the Milestone 1 budget. If it is not, return to Milestone 1 before
  buying the remaining cameras.
- The chosen PTZ model is confirmed to actually autotrack, not merely to accept PTZ commands.

---

## Milestone 4 — Power subsystem

Build and commission the off-grid power system sized in Milestone 1, before the site install
depends on it.

**Deliverables**

- `power/as-built.md`: array layout, controller and inverter models, battery configuration,
  disconnects, fusing, and grounding.
- Battery and charge-controller telemetry exported into the monitoring stack — state of charge,
  net charge/discharge, and days-of-autonomy-remaining are operational metrics for this project in
  the same way disk usage is.
- `docs/runbooks/low-power.md`: the documented degradation ladder for a low-state-of-charge event.
  Which cameras shed first, at what threshold recording drops to alerts-only, and at what threshold
  the hub shuts down cleanly rather than browning out mid-write.

**Exit criteria** — the system carries the Milestone 3 measured load through a full night plus a
simulated low-generation day without dropping below the reserve threshold, and the shed ladder has
been triggered deliberately at least once.

---

## Milestone 5 — Site install and phase 1 rollout

This is the existing Phase 1 from the README, now with its prerequisites satisfied.

**Deliverables**

- Cameras mounted, cabled, and entered into `network/ip-inventory.md`.
- Per-camera Frigate includes committed: zones, motion masks, and detection regions, plus the
  night-vision mitigations already described in the plan (sky and ground masked out, raised
  nighttime threshold, camera angles set to avoid IR bounce).
- `motion.contour_area` and `motion.threshold` tuned per camera from Frigate's motion-tuning view
  rather than left at the global values in the original plan (finding C3).
- `docs/runbooks/add-camera.md`: the repeatable procedure, written while adding the first cameras.

**Exit criteria** — every camera records on motion, retention prunes correctly, and the false-positive
rate is low enough that the alert stream is worth reading. Detection FPS has measurable headroom
against Coral capacity.

---

## Milestone 6 — Observability and alerting

The README's monitoring table is a good specification; this milestone implements it.

**Deliverables**

- Prometheus and Grafana in the Compose stack, with exporters for host, disk, Frigate, and the
  power subsystem.
- Alert rules implementing the thresholds already specified: disk usage 80/90%, daily write
  200/300 GB, detection rate 50/100 per hour, Coral utilization 70/85%, PTZ activity 50/100 events
  per hour — plus battery state of charge and camera-offline alerts.
- A Coral watchdog that detects a TPU dropping off the USB bus and restarts or resets it
  (finding H2).
- `docs/runbooks/alerts.md`: for each alert, what it means and what to do about it.

**Exit criteria** — every threshold in the monitoring table has a corresponding live alert with a
documented response, and each has fired at least once in a deliberate test.

---

## Milestone 7 — Backup and disaster recovery

**Deliverables**

- Configuration backup: this repository is the backup, so the working configuration on the hub is
  reconciled against the repository automatically and drift is reported.
- Footage backup: the tiered archive plus offsite sync for flagged clips only, not bulk footage —
  bandwidth on an off-grid uplink makes bulk sync impractical.
- `scripts/backup.sh` and `scripts/restore.sh`, scheduled and monitored.
- `docs/runbooks/disaster-recovery.md`: rebuild from bare hardware using only this repository and
  the backup target.

**Exit criteria** — a restore drill has been performed on scratch hardware or a wiped install, and
the time it took is recorded. An untested backup is not a backup.

---

## Milestone 8 — Automation depth and expansion

The remaining phases from the original plan, gated on the earlier milestones being stable.

**Deliverables**

- Home Assistant automations for chain camera activation (doorbell motion triggering the interior
  entry camera), cross-camera tracking handoff, and notification routing with tracking status.
- Zigbee door and window sensors integrated, if that decision closes in favour of physical sensors.
- Expansion to the full camera count, gated on measured storage, detection, and power headroom.
- Tracking cooldowns and zone restrictions tuned against observed PTZ activity rather than assumed
  values.

**Exit criteria** — the system runs unattended for an extended period with no manual intervention,
and every automation has a documented failure mode.

---

## Decision log seed

Three of the nine open questions in the README can be closed now from the review; the rest are
gated on the milestones shown.

| Question | Recommendation | Status |
| --- | --- | --- |
| Remote access: Tailscale or Cloudflare Tunnel | Tailscale. Cloudflare's terms discourage video through the CDN, and an off-grid uplink behind CGNAT rules out port forwarding anyway (M6). | Ready to close |
| Storage layout / RAID level | Drop RAID 5. Tiered NVMe hot plus mirrored SATA archive, per C2. | Ready to close |
| Coral count | Two, required rather than optional at the 20-camera target, per H2. | Ready to close |
| PTZ camera brand and model | Select from Frigate's verified autotracking list only; verify `PTZRelative` support before purchase (H1). | Milestone 1 |
| Camera mix and count | Mostly fixed, 2–4 PTZ. Final count gated on the power budget (C1, H1). | Milestone 1 |
| Storage expansion budget | Recost after the power subsystem is priced; consider HDD for cold archive as the plan already suggests. | Milestone 1 |
| Backup strategy for critical footage | Flagged clips offsite, bulk footage local only — uplink-constrained. | Milestone 1 |
| PoE switch capacity | Size the PoE budget against measured camera draw once the camera mix is fixed; 16-port versus 24-port falls out of that. | Milestone 1 |
| Physical door/window sensors versus camera-based AI | Both: Zigbee sensors are cheap, low-power, and work in the dark and in bad weather where the cameras degrade. | Milestone 8 |
| Home Assistant integration depth | Defer until Frigate alone is stable. | Milestone 8 |
| Motion tracking sensitivity thresholds | Cannot be answered in the abstract — tune per camera from observed footage. | Milestone 5 |

## Critical path

Milestone 1 is the gate on everything physical. The power budget determines the camera mix, the
camera mix determines the switch and Coral sizing, and all of it determines whether the project's
total cost is acceptable — a question that cannot currently be answered because the largest cost
item has never been estimated. Milestone 0 and Milestone 2 have no hardware dependency and can
proceed in parallel with it.
