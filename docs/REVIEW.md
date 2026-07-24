# Repository Review

Review date: 2026-07-24
Reviewed commit: `586b4e1`
Scope: entire repository (`README.md` only)

## Summary

The repository is a design document, not a project. It contains one file — a well-organized
planning summary for a ZimaBoard 2 based Frigate NVR — and no configuration, code, scripts, or
automation of any kind. Nothing in the repository can currently be deployed, validated, or tested.

The design itself is broadly sound for a *mains-powered* 12–20 camera Frigate build. The hardware
choices are appropriate, the storage estimates are in a realistic range, and the phased rollout is
sensible. Three classes of problem need to be resolved before the plan is buildable:

1. **The off-grid requirement in the project name is entirely unaddressed.** There is no power
   budget, no solar or battery sizing, and no off-grid cost line. This is the largest gap, and it
   changes the total project cost by more than the current budget itself.
2. **Several internal contradictions** exist between sections — most importantly the storage
   tiering plan contradicts the chosen RAID level, and the link-aggregation recommendation
   contradicts the network architecture.
3. **The Frigate configuration snippet is not valid Frigate config.** Both the PTZ block and the
   recording-retention block use keys that do not exist in current Frigate.

Findings are listed below by severity. Each one is actionable; the corresponding work is scheduled
in [`ROADMAP.md`](./ROADMAP.md).

---

## Critical findings

### C1. No off-grid power design exists

The repository is named `Off_grid_home_security_hub`, but the document treats power as a
mains-connected concern: the only power content is a UPS recommendation and generic efficiency tips.
An off-grid deployment needs a load budget, generation sizing, storage sizing, and a winter-worst-case
analysis, none of which are present.

A rough load budget for the design as written:

| Load | Continuous draw |
| --- | --- |
| ZimaBoard 2 (idle to sustained load) | 10–25 W |
| 2× Coral USB TPU | ~4 W |
| NVMe + 2× SATA SSD | ~10 W |
| Managed PoE+ switch (chassis overhead, before PoE) | 20–40 W |
| 12–20 PTZ speed domes @ ~12–20 W each (IR and motors active) | 150–400 W |
| PoE conversion losses (~15%) | 25–60 W |
| Internet uplink (a satellite terminal averages 45–75 W) | 0–75 W |
| **Total** | **~220–615 W** |

At a midpoint of ~350 W continuous that is **~8.4 kWh/day**. Sizing generation and storage against
that figure:

- **Solar array:** at 4 peak-sun-hours and ~75% system efficiency, ~2.8 kW. At a winter
  2.5 peak-sun-hours, ~4.5 kW.
- **Battery bank:** two days of autonomy is ~17 kWh usable, i.e. roughly a 20 kWh LiFePO4 bank.
- **Balance of system:** MPPT charge controller, inverter/charger, racking, wiring, disconnects.

At current pricing that subsystem lands somewhere around **$6,000–10,000**, which is larger than the
entire budget the document currently states ($2,300–4,650). The off-grid power system is the
dominant cost of this project and it is not in the plan.

This finding does not mean the design is wrong — it means the design has not yet been costed or
sized against its stated deployment context. Section "Off-grid power" of the roadmap lists the
mitigations that bring the load down substantially (DC-native distribution, fixed cameras instead of
PTZ for most positions, disabling IR heaters, duty-cycling low-priority cameras).

### C2. Storage tiering and the selected RAID level are mutually exclusive

The Storage Architecture table assigns distinct roles per device — NVMe for active recordings, the
two SATA SSDs for archive and redundancy. The Storage Configuration Options table then selects
"RAID 5 for 8 TB usable", which requires striping all three devices into a single array.

These cannot both be true. Building RAID 5 across one PCIe NVMe drive and two SATA SSDs also
throttles the array to SATA speed and discards the entire benefit of the NVMe, while adding
parity-write overhead on a 6 W CPU.

Recommendation: keep the tiering and drop RAID 5. Use the NVMe for the OS overflow, Docker state,
Frigate's database, and the hot recording tier; mirror or sync the two SATA devices for the archive
tier. Note also that RAID is not a backup — three identical SSDs bought together will wear out
together, which makes finding C4 more important.

### C3. The Frigate configuration snippet will not load

Two of the four blocks in the "Frigate Configuration Highlights" section use keys that do not exist
in Frigate:

- **PTZ.** The snippet uses a top-level `ptz: auto: {mode, position, timeout, smooth}`. Frigate has
  no top-level `ptz` key. Autotracking is configured per camera under
  `cameras.<name>.onvif.autotracking`, with keys `enabled`, `calibrate_on_startup`, `zooming`,
  `zoom_factor`, `track`, `required_zones`, `return_preset`, `timeout`, and `movement_weights`.
  There is no `smooth` option; movement smoothness comes from the calibration-generated
  `movement_weights`. `required_zones` and `return_preset` are effectively mandatory for usable
  autotracking.
- **Recording retention.** The snippet uses `record.events.retain.{default,mode}`, which was the
  pre-0.14 schema. Current Frigate uses `record.retain.{days,mode}` for the base policy and separate
  `record.alerts.retain` / `record.detections.retain` blocks for review-item retention. Note that
  the `continuous:` / `motion:` keys visible in Frigate's `dev` documentation are 0.17-only and will
  fail on 0.16.

The `detect`, `motion`, and `objects` blocks are valid. `motion.contour_area: 40` is well above the
default and will suppress genuine distant motion; it should be tuned per camera from Frigate's
motion-tuning UI rather than set globally up front.

A corrected, current-schema version of this configuration is the first deliverable in the roadmap.

---

## High-severity findings

### H1. Autotracking on all 12–20 cameras is not a realistic target

The document specifies PTZ speed domes with autotracking on every camera. Three problems:

- **Compatibility.** Frigate autotracking requires ONVIF *relative* movement
  (`PTZRelative` / `PTZRelativePanTilt` / `PTZRelativeZoom`). Many ONVIF Profile S cameras expose
  PTZ controls but not relative movement, and some advertise it and still fail. The camera model
  must be verified against Frigate's supported-camera table before purchase, not after.
- **Coverage.** A camera that has slewed to follow a subject is no longer watching its assigned
  scene. Making every camera an autotracker means every camera can be pulled off its post by a
  single moving subject, which is a well-known way to create coverage gaps.
- **Cost.** The budget allots $1,200–3,000 for 12–20 PTZ cameras, i.e. $100–150 each. Autotracking-
  capable ONVIF speed domes with 30 m+ IR realistically run $150–400 each. The camera line item is
  understated by roughly 2×.

Recommendation: mostly fixed cameras for coverage, with 2–4 PTZ autotrackers on approach paths and
high-value zones. This also cuts the power budget in C1 substantially.

### H2. Coral sizing is stated as a range where the requirement is determinate

The document says "1–2 units". The arithmetic is fixed: a USB Coral runs ~10 ms per inference, so it
tops out near 100 inferences/second. Twenty cameras at 5 detect-FPS is exactly 100/s at saturation,
with zero headroom. The repository title already says "Dual Coral", so plan for two and treat the
second as required at the 20-camera target rather than as an upgrade.

Two constraints follow that the document does not mention:

- Both USB Corals share the ZimaBoard's USB controller, and USB Corals are widely reported to
  degrade (25 ms+) or drop off the bus entirely under thermal or bus contention. A watchdog and
  good airflow around the accelerators are not optional on a fanless chassis.
- Because the single PCIe 3.0 x4 slot is consumed by the NVMe carrier, the faster M.2 dual Edge TPU
  is not straightforwardly available. Using it would require a multi-slot carrier and PCIe
  bifurcation support that the N150 platform is unlikely to provide. Confirm this before buying.

Worth noting in the project's favour: Frigate's current hardware guidance de-recommends Coral for
new builds *except* in low-power deployments — which is precisely this deployment. The choice is
defensible, it just needs to be a documented, deliberate one.

### H3. Link aggregation contradicts the network architecture

The network diagram assigns Port 1 to the camera VLAN and Port 2 to management/remote access.
Recommendation 3 then suggests bonding both 2.5GbE ports for 5 Gbps. Only one of these is possible
on a two-port board.

The bond is also unnecessary. Twenty cameras with a main stream at 4–6 Mbps and a sub-stream at
~1 Mbps is roughly 100–140 Mbps aggregate — under 6% of a single 2.5GbE link. Keep the physical
separation and drop the aggregation idea, or move to VLAN trunking on one port if a second
interface is needed elsewhere.

### H4. No secrets-handling or configuration-hygiene plan

The plan involves RTSP credentials, ONVIF credentials, an MQTT broker, and a Home Assistant
instance, and Recommendation 7 proposes keeping the configuration in a Git repository — this one.
There is no mention of how credentials stay out of the repository. Frigate supports `FRIGATE_`-prefixed
environment variables and Docker secrets for exactly this; the repository needs a `.gitignore`, an
`.env.example`, and a stated rule that no config file containing a live credential is ever committed.

---

## Medium-severity findings

### M1. Hardware acceleration is not specified

Twenty camera streams cannot be decoded in software on a four-core N150. The N150's integrated
graphics provide Quick Sync decode for H.264 and H.265, so `hwaccel_args` must be set (the
`preset-intel-qsv-*` presets) and the container needs `/dev/dri` passed through. This is a
functional requirement for the stated camera count, not an optimization, and it is absent from the
document.

### M2. go2rtc restreaming is not mentioned

Without restreaming, every consumer — Frigate recording, Frigate detection, the live UI, Home
Assistant, a phone app — opens its own connection to the camera. Cheap cameras cap concurrent RTSP
sessions and degrade under load. Frigate bundles go2rtc precisely to consolidate this into one pull
per camera; the design should route all streams through it.

### M3. The eMMC is treated as general-purpose storage

The ZimaBoard's 64 GB eMMC is fine for the base OS and poor for anything write-heavy. Docker's
data root, Frigate's SQLite database, and any logging must be relocated to the NVMe, or the eMMC
becomes the first component to fail.

### M4. Shared-memory and cache sizing is unaddressed

Frigate's default 64 MB `shm_size` is far too small for 12–20 cameras and produces confusing
crashes rather than clear errors. Both `shm_size` and the `/tmp/cache` tmpfs need to be sized from
Frigate's documented formula and recorded in the compose file.

### M5. Time synchronization is unaddressed in an off-grid context

Recording timestamps are the property that makes footage useful after an incident. An off-grid site
may have an intermittent or absent uplink, and the ZimaBoard has no battery-backed RTC guarantee to
rely on. A local time source (GPS-disciplined or a hardware RTC module) plus a local NTP server for
the camera VLAN should be part of the build.

### M6. Cloudflare Tunnel versus Tailscale is presented as an open coin-flip

For continuous video, these are not equivalent. Cloudflare's terms restrict serving large volumes
of non-HTML content such as video through its CDN, which makes streaming an NVR through a Tunnel a
poor fit. Additionally, an off-grid site is likely on a satellite or cellular uplink behind CGNAT,
where inbound port forwarding is impossible regardless. A WireGuard-based mesh such as Tailscale
traverses CGNAT, does not proxy the video through a third party, and is the appropriate default.
This decision can be closed now rather than deferred.

### M7. The budget omits several required line items

Missing entirely: cabling and terminations, camera mounts and junction boxes, the UPS the document
itself recommends, surge protection, enclosure and cooling, and the whole off-grid power subsystem
from C1. The PoE+ switch line ($100–200) is also low — a 24-port 2.5GbE PoE+ switch with a
sufficient power budget for 20 PTZ cameras is a several-hundred-dollar item, and its PoE budget
needs to be calculated against actual camera draw rather than assumed.

---

## Low-severity findings

### L1. The README does not render as Markdown

Every table in the document is tab-separated rather than pipe-delimited, so GitHub renders the
tables as run-together paragraphs. Section headings have no `#` prefixes, and the YAML block is not
fenced. The document's structure is invisible to a reader on GitHub. This is fixed in the
accompanying commit.

### L2. The document is a session transcript rather than a specification

It ends with a question to the reader, is versioned as "Version 3.0" in prose, and mixes settled
decisions with open ones throughout. That is fine as a record of a planning session, but the
project needs a specification that states what is being built, and a separate decision log for what
is still open. The roadmap proposes that split.

### L3. Repository hygiene

No `LICENSE`, no `.gitignore`, no CI, no issue templates, no contribution or operating notes. For a
single-maintainer home-lab repository the license and gitignore are the ones that matter, and
`.gitignore` matters most given H4.

---

## What is good and should not change

- The core hardware selection is well matched to the workload: an N150 with Quick Sync, 16 GB of
  RAM, and Coral offload is a sensible, low-power Frigate host, and low power is the right thing to
  optimize for here.
- Motion-triggered recording with a 5 FPS detection sub-stream is the correct baseline; it is the
  single largest determinant of storage cost and it was chosen correctly.
- The storage estimates (~120–420 GB/day depending on camera count and activity) are in a
  believable range and leave real headroom against the planned capacity.
- VLAN segmentation of cameras with no inbound port forwarding is the right security posture.
- The phased rollout — validate 12 cameras before expanding, tune detection before enabling
  tracking — is the correct order of operations and should be kept as written.
- The monitoring thresholds table is unusually good for a plan at this stage; it just needs to be
  implemented rather than described.
