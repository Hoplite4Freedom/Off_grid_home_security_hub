# Technical Review — Off-Grid Home Security Hub

Review date: 2026-07-24
Reviewed artifact: `README.md` (Session Summary v3.0, dated 2026-03-15)
Reviewer scope: design feasibility, correctness against upstream documentation, cost realism, repository readiness

## Summary

The repository contains one artifact: a planning document pasted from a chat session. There is no code,
no configuration, no bill of materials with real part numbers, and no deployment tooling. Nothing in the
repository is executable or verifiable today.

The design itself is directionally sound — Frigate on an x86 mini-server with an Edge TPU, motion-only
recording, VLAN-isolated cameras and tunnel-based remote access is a well-trodden and appropriate
architecture. The problems are concentrated in five areas: the off-grid power requirement is entirely
unaddressed despite naming the project, the storage architecture contradicts itself and does not fit the
board's expansion slots, the sample Frigate configuration does not match current Frigate schema,
autotracking on every camera is not achievable as specified, and three budget lines are understated by
roughly 2–3×.

None of these are fatal. All of them are cheaper to fix now than after hardware is purchased.

## Findings

Severity key: **B** = blocker (resolve before buying hardware), **M** = medium (resolve before or during
deployment), **L** = low (repository hygiene).

### B1 — Off-grid power is not designed, budgeted, or mentioned

The repository is named `Off_grid_home_security_hub` and the planning document never addresses power
generation or storage. The only power content is a UPS line item and some efficiency tips, which describe
a grid-tied system with outage protection — not an off-grid one.

Rough load model for the design as written:

| Load | Count | Watts each | Subtotal |
| --- | --- | --- | --- |
| Fixed PoE camera (4MP, IR on at night) | 16 | 5–10 W | 80–160 W |
| PTZ speed dome (PoE+, higher with heater/defog) | 4 | 8–25 W | 32–100 W |
| PoE switch overhead + conversion loss | 1 | 20–45 W | 20–45 W |
| ZimaBoard 2 + NVMe + 2× SSD + 2× Coral | 1 | 20–30 W | 20–30 W |
| **Total continuous** | | | **150–335 W** |

That is roughly **3.5–8 kWh/day**, with the high end occurring at night when IR illuminators and heaters
are active and solar input is zero. Sizing an off-grid supply for the midpoint (~5.5 kWh/day) at four peak
sun hours, ~70% system efficiency, and two days of autonomy at 80% depth of discharge implies roughly a
**2 kW PV array and a 14 kWh LiFePO4 bank**, which lands somewhere around **$4,500–8,800** for panels,
battery, charge controller and inverter. That exceeds the entire current project budget of $2,289–4,639.

This finding gates almost every other decision, because the power budget determines how many cameras the
system can support, and camera count determines detector load, storage consumption, switch size and
retention. It should be resolved first.

Two useful levers:

- **Camera count and type dominate the load.** Twelve fixed cameras with no PTZ is roughly 100–140 W
  (~3 kWh/day) and nearly halves the generation requirement versus twenty cameras with four PTZs.
- **Stay DC-coupled.** Every load here is natively DC (12 V for the board, 48 V for PoE). Feeding the PoE
  switch and the board from a 48 V battery bank through DC-DC converters avoids the 10–15% round-trip
  loss of inverting to AC and back, and removes the inverter from the failure path.

### B2 — The storage architecture contradicts itself and does not fit the board

The document specifies two mutually exclusive designs. The Storage Architecture table describes a tiered
layout (4 TB NVMe for active recordings, 2× 4 TB SATA for archive/redundancy), and the Storage
Configuration Options section then states "Selected: RAID 5 for 8 TB usable capacity." A RAID 5 array
across all three devices merges the tiers into one volume, pins the NVMe to SATA throughput, and applies
a read-modify-write parity penalty to every recording write. The later "Tiered Storage" efficiency
recommendation contradicts the RAID 5 selection a second time.

The hardware constrains this further. The ZimaBoard 2 has **two SATA 3.0 ports and one PCIe 3.0 x4 slot**.
Using the PCIe slot for an NVMe adapter consumes the only expansion slot, so there is no remaining slot
for a SATA HBA (to reach more drives) or for an M.2 AI accelerator. The three-device RAID 5 as described
is buildable only by mixing one NVMe and two SATA devices in an mdadm array, which is the worst of both
worlds.

Recommended resolution: keep the tiers and drop RAID 5. Put the OS, the Frigate database and the
`/tmp/cache` write buffer on the NVMe along with the most recent day or two of recordings, and use the two
SATA bays for bulk retention. Frigate benefits specifically from having its database and cache on fast
media while recordings live on slower media, so the tiering is worth preserving. Redundancy for a
surveillance array is better served by a tested offsite/offline copy of what matters (configs plus alert
clips) than by parity across three devices in the same chassis — RAID protects against a drive failure,
not against theft of the chassis, which is the more relevant threat for a security recorder.

Whether the bulk tier should be SSD or HDD is a genuine trade-off rather than an obvious call. Two
surveillance-grade CMR HDDs save roughly $400–600 against SSDs, but draw 10–16 W continuously
(~0.3 kWh/day off-grid), add heat and vibration to a fanless aluminum chassis, and reintroduce spin-up
latency. If the off-grid power budget from B1 comes out tight, the SSD premium is buying real watts and is
defensible. Decide this after the power budget is fixed, not before.

### B3 — The sample Frigate configuration will not load on current Frigate

Three problems, all of which cause validation failures or silently do nothing:

1. **The `ptz:` top-level block does not exist.** Autotracking is configured per camera under
   `cameras.<name>.onvif.autotracking`, with keys `enabled`, `calibrate_on_startup`, `zooming`,
   `zoom_factor`, `track`, `required_zones`, `return_preset`, `timeout` and `movement_weights`. The
   document's `mode: on_event`, `position: home` and `smooth: true` are not Frigate keys at all.
2. **`record.retain` and `record.events` are the pre-0.15 schema.** Current Frigate uses
   `record.continuous.days` and `record.motion.days` for time-based retention, and
   `record.alerts.retain` / `record.detections.retain` for object-based retention. `mode: active_objects`
   remains valid inside those retain blocks.
3. **Everything required to actually run is missing**: `mqtt`, `detectors`, `go2rtc` restreaming,
   `ffmpeg.hwaccel_args`, per-camera inputs with `detect`/`record` role assignment, `snapshots`, zones,
   motion masks, and `auth`.

The document presents this block as "Configuration Highlights," so this is a documentation-accuracy
problem rather than a broken deployment — but it is the artifact most likely to be copied verbatim into a
first install, and it will fail.

### B4 — Autotracking on all 12–20 cameras is not achievable as specified

The document states "Motion Tracking: Auto-tracking enabled on all cameras" and budgets tracking overhead
accordingly. Four constraints make this unrealistic:

- **Hardware support is narrow.** Frigate autotracking requires ONVIF relative movement within the field
  of view (`RelativePanTiltTranslationSpace` with a `TranslationSpaceFov` entry). Many cheaper and older
  PTZs do not implement it, and some advertise it while failing to honor it. Hikvision PTZs are documented
  as not updating the ONVIF `MoveStatus` parameter, which breaks autotracking with no workaround.
- **It is one object per camera.** Autotracking follows a single tracked object; it is not a way to watch
  a scene more thoroughly.
- **A tracking PTZ is blind everywhere else.** While the camera is following someone across the yard, the
  area it was previously covering is unmonitored. Twenty tracking cameras is twenty cameras that can each
  be lured off-station.
- **Frigate's own recommended pattern is different**: fixed "spotter" cameras detect, and an automation
  moves a small number of PTZs to a preset covering that area, where autotracking then takes over.

Recommended resolution: two to four PTZs on models verified to work, with fixed cameras everywhere else.
This also removes most of the mechanical-wear, false-trigger and PTZ-cycling concerns the document raises
later, and it reduces cost and power.

Before committing to a PTZ fleet, buy **one** candidate camera and verify relative-FOV movement with
ONVIF Device Manager and a Frigate calibration run. The community-maintained compatibility list is the
starting point; Frigate's autotracking was developed against a Dahua/EmpireTech SD1A404XB-GNR.

### B5 — Three budget lines are understated by roughly 2–3×

| Line | Document | Realistic | Note |
| --- | --- | --- | --- |
| PTZ cameras (12–20) | $1,200–3,000 | $200–350 each for autotrack-capable outdoor PoE PTZ | $60–150/camera buys consumer WiFi pan-tilt units that fail the B4 requirements |
| Managed 2.5GbE PoE+ switch | $100–200 | $500–1,200 for 24-port 2.5GbE PoE+ | See below — 2.5GbE to cameras is unnecessary |
| Off-grid power subsystem | absent | $4,500–8,800 at 20 cameras, less if scoped down | See B1 |

Also missing from the bill of materials: PoE cabling and terminations, weatherproof junction boxes,
mounting hardware, the PCIe-to-NVMe adapter the board requires, a rack or enclosure, and spares.

One offsetting saving: **2.5GbE to the cameras is over-specified.** Twenty cameras at 8 Mbps main plus
2 Mbps sub is roughly 200 Mbps aggregate — a fraction of a single gigabit link. A 16- or 24-port **1GbE**
PoE+ switch with 2.5G uplinks does the job for several hundred dollars less and often at lower idle power,
which matters off-grid. Specify the switch by **PoE budget** (plan ~15 W average per camera plus 15%
headroom, so 300 W+ for 20 cameras) rather than by port speed.

### M1 — The dual-Coral premise needs revisiting (though it survives review)

Frigate's current documentation states the Coral is **no longer recommended for new installations**,
"except in deployments with particularly low power requirements or hardware incapable of utilizing
alternative AI accelerators." Google has the Coral line in maintenance mode with no significant updates
since 2023.

The exception is exactly this deployment, so keeping Coral is defensible — but the reasoning should be
recorded, along with two constraints the document misses:

- **Both Corals must be USB on this board.** The single PCIe x4 slot is consumed by the NVMe adapter
  (B2), so the M.2 dual Edge TPU and the Hailo-8 M.2 are both off the table unless storage changes. USB
  Corals lack the automatic thermal throttling of the M.2 versions and are known to drop off the bus
  under sustained load; plan for a powered hub or extension cable away from the chassis heat, and monitor
  for detector restarts.
- **The N150 iGPU is a zero-extra-hardware fallback.** Frigate reports ~15 ms MobileNetV2 and ~16 ms
  YOLOv9-t-320 inference on the N150 via OpenVINO. That is a ~66 fps detection ceiling and the N100 is
  documented as supporting only one detector instance, so it will not cover 20 cameras at peak — but it
  is a working degraded mode if a Coral fails, and it is worth configuring and testing as such.

Sizing check on the dual-Coral decision: a Coral at ~10 ms inference tops out near 100 detections/sec.
Twenty cameras at 5 detect fps is 100/sec *if every camera has motion simultaneously*, which is the
pathological case, but a single Coral would have no headroom at all. Two is the right call.

### M2 — "Distribute cameras across 2 Coral TPUs" describes a mechanism that does not exist

Frigate runs one process per configured detector, but all detectors **pull from a common queue shared
across all cameras**. You cannot assign specific cameras to specific TPUs. The outcome the document wants
(more detection capacity) is correct; the mechanism is not. Configure two `edgetpu` detectors on `usb:0`
and `usb:1` and let Frigate schedule.

### M3 — No hardware acceleration, restreaming, or shared-memory plan

The document has no `ffmpeg` strategy, which is the most common cause of failed multi-camera Frigate
builds. Three things need to be in the config:

- **`hwaccel_args` for Intel QuickSync (VAAPI).** The Coral does not decode video; the CPU does. Four
  N150 cores will not sustain twenty decoded detect streams in software. The N150 has a hardware
  transcode engine covering H.264 and H.265 up to 4K60.
- **`copy` for record streams.** Recording should never re-encode; take the camera's main stream as-is.
- **`go2rtc` restreaming** so that live view, recording and detection share one connection per camera
  rather than each opening its own.

Also size `shm_size` for the container explicitly — the 64 MB Docker default is far too small at this
camera count — and keep Frigate's frame cache on tmpfs or the NVMe rather than the bulk tier.

### M4 — H.265 recommendation needs a compatibility caveat

The efficiency section recommends H.265 for a 40–50% storage reduction, which is real, but H.265
recordings play back only in Chrome 108+, Edge and Safari; other browsers require H.264. Frigate provides
an Apple-compatibility option for Safari playback. A reasonable split is H.265 on the main/record stream
and H.264 on the detect substream, where the bitrate saving is negligible and decode compatibility and
cost matter more.

### M5 — Storage estimates are plausible but should be treated as hypotheses

The figures work out to roughly 10–21 GB per camera per day, which is a reasonable motion-only estimate
for 4MP main streams at a moderate duty cycle, and the 10-day totals fit inside 8 TB. But they are
derived from assumptions about activity level that no one has measured yet at this site. Treat them as a
Phase 1 measurement target rather than a design input: record actual GB/camera/day for two weeks before
buying the final storage tier.

### M6 — Security plan has gaps

The VLAN, tunnel, TLS and 2FA choices are right. Missing:

- **Explicit deny-egress for the camera VLAN.** VLAN membership alone does not stop cameras reaching the
  internet; that requires a firewall rule. This is the single highest-value control for IP cameras, which
  have a poor firmware track record. Cameras need NTP and nothing else.
- **A local NTP source.** With no internet egress, cameras need an internal NTP server, or timestamps
  drift and recording correlation breaks.
- **Frigate's own authentication.** Frigate has built-in auth; the tunnel is not the only layer that
  should exist.
- **Secrets handling.** Camera credentials, MQTT credentials and API keys must not land in this git repo.
  Plan for `.env` files excluded via `.gitignore`, or Frigate's secrets support, from the first commit —
  retrofitting after a leak means rotating every camera password.
- **A firmware update policy** for cameras that are deliberately cut off from the internet.
- **UPS integration, not just a UPS.** The document cites data corruption as the UPS rationale, but a UPS
  with no NUT (or equivalent) integration does not shut the host down cleanly — it just delays the
  uncontrolled power loss. Off-grid, this doubles as the low-battery shutdown path.

### M7 — Privacy and legal considerations are absent

Not legal advice, but three items belong in the design: audio recording is restricted or requires consent
in many jurisdictions and is often best disabled outright; camera framing that covers neighbouring
property or public walkways may require privacy masks (Frigate supports motion masks, and most cameras
support firmware-level privacy masks); and some jurisdictions require signage or impose retention limits.
The 7–10 day retention choice is as much a legal posture as a storage one.

### M8 — The monitoring table has thresholds but no implementation

The warning/critical thresholds for disk usage, daily write, detection rate, Coral utilization and PTZ
activity are good operational instincts, but nothing collects or evaluates them. Frigate exposes
`/api/stats`, which a Prometheus exporter or a Home Assistant template sensor can scrape. Without that,
these numbers are aspirations. This is Phase 7 work, not day one, but the table should be marked as
unimplemented until it is wired up.

### L1 — Every table in the README is broken

All ~25 tables are tab-separated rather than Markdown pipe tables, so GitHub renders each one as a single
run-on paragraph. The document is significantly harder to read on GitHub than it was in the chat session
it came from. This is a mechanical fix.

### L2 — The README is a chat transcript, not a repository README

It opens with session metadata ("Session Type: Technical Planning & Architecture Design") and closes with
a question addressed to a chat assistant ("Would you like me to create a separate configuration template
file..."). A repository README should orient a reader — what this is, what state it is in, how to deploy
it — with the session notes preserved separately as design history.

### L3 — No repository scaffolding

No `LICENSE`, no `.gitignore`, no config templates, no deployment tooling, no changelog, and the nine
open decisions live in a table in a README where they cannot be tracked or assigned. Version "3.0" has no
corresponding history.

## What is already right

Worth stating explicitly, because the path to completion should not relitigate these:

- Frigate + MQTT + Home Assistant + Docker on Debian is the correct stack for this problem.
- Motion-triggered recording with a 5 fps detect substream and a separate full-rate record stream is the
  right performance model, and 5 fps matches Frigate's own guidance for autotracking.
- Dual NICs with a separate camera VLAN is the right network topology, and this board's two 2.5GbE ports
  suit it.
- Tailscale or Cloudflare Tunnel instead of port forwarding is the right remote-access posture.
- Two Corals is correctly sized for the stated camera count (see M1).
- The phased rollout instinct — deploy 12, measure for two weeks, then expand — is exactly right and
  should be kept as the spine of the plan.
