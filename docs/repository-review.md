# Repository Review

Reviewed: 24 July 2026 · Against `README.md` v3.0 (dated 15 March 2026) · Frigate 0.17.x as the current stable line

## What the repository is today

The repository contains exactly one file: a `README.md` holding the transcript of a planning
conversation. There is no code, no configuration, no license, no `.gitignore`, no issue tracker
usage, and no branches other than `main` (two commits, both README edits).

That means the project is at the "design intent captured" stage. Nothing in the repository can be
deployed, validated, or tested, and nothing prevents the design from drifting as decisions get made
verbally. The design content itself is broadly sound as a starting point — the phased rollout,
motion-triggered recording, sub-stream detection, VLAN isolation, and tunnel-based remote access are
all the right instincts — but several numbers and configuration snippets will not survive contact
with the hardware, and one entire subsystem implied by the repository's own name is missing.

The findings below are ordered by severity. Blockers change the shape of the build; majors change
the bill of materials or the configuration; minors are cheap corrections worth folding in.

## Blockers

### B1. The project is named "off grid" but there is no power system in the design

`Off_grid_home_security_hub` implies generation, storage, and load management. The README's only
power content is a UPS line item and a suggestion to spin down hard drives. Off-grid operation is
not a component you add at the end — it sets the camera count, the camera type, the accelerator
choice, and the storage medium. It has to be designed first.

Rough load budget for the design as written (20 PTZ cameras, mains-style assumptions):

| Load | Assumption | Continuous draw |
| --- | --- | --- |
| PTZ cameras | 20 × ~12 W average (IR and motor active part of the time) | ~240 W |
| PoE delivery and switch overhead | ~15% cable/conversion loss plus ~25 W switch base | ~60 W |
| ZimaBoard 2 | 6–8 W idle, 12–15 W under sustained load | ~15 W |
| 3 × SSD + accelerator | | ~8 W |
| **Total** | | **~325 W → ~7.8 kWh/day** |

Supporting 7.8 kWh/day off-grid needs roughly a 2.5–3 kW array (assuming 4 peak-sun-hours and ~72%
end-to-end efficiency) and 16–20 kWh of usable battery for two days of autonomy. That is a
$5,000–11,000 power system sitting on top of a compute budget the README puts at $2,300–4,650.

The same budget with fixed-lens turret cameras (5–8 W each) instead of PTZs lands near 4.0 kWh/day,
which halves the array and battery. This is the single highest-leverage decision in the project, and
it is currently being made implicitly by the camera selection.

Two off-grid consequences the design has not accounted for:

- **The WAN link is a major load.** Starlink draws 45–75 W continuously, which is 1.1–1.8 kWh/day —
  comparable to the entire server and storage stack. Cellular is far cheaper power-wise but caps
  remote video review.
- **Alerting must degrade gracefully.** Every notification path in the design (push notifications,
  Cloudflare Tunnel, Tailscale) depends on the WAN link. Off-grid links go down. The system needs a
  local annunciator path — siren, indoor display, or local-network push — that works with no
  internet at all, plus a battery state-of-charge-driven load-shedding policy that reduces camera
  count or frame rate before the battery hits a damaging depth of discharge.

### B2. The hardware has one PCIe slot and the design needs it twice

The ZimaBoard 2 1664 has 2 × SATA III, 1 × PCIe 3.0 x4, and 2 × USB 3.1. The design calls for three
4 TB drives (which consumes both SATA ports plus the PCIe slot for an NVMe carrier) *and* an AI
accelerator. The N150's PCIe x4 link is not expected to support bifurcation, so a dual-M.2 carrier
that hosts both an NVMe drive and an M.2 accelerator is not a safe assumption.

The design implicitly resolves this by using USB Corals, which is the weakest of the available
options: both units share a single USB controller, and Frigate users report that a second USB Coral
often yields little additional throughput because the host USB bus becomes the bottleneck.

Three workable allocations, in order of preference:

1. **Two SATA drives for storage, PCIe slot for the accelerator.** Drop to 2 × 4 TB (4 TB usable
   mirrored, or 8 TB striped/spanned) — which still comfortably exceeds the 1.8–4.2 TB the retention
   math actually calls for — and put a Hailo-8 M.2 or Coral M.2 in the PCIe slot. Cleanest, lowest
   power, no USB bottleneck.
2. **No discrete accelerator at all.** The N150's iGPU runs OpenVINO at roughly 15 ms inference
   (~67 detections/sec), which covers 12 cameras at 5 fps detect with margin. This frees the PCIe
   slot for the third drive, costs nothing, and adds no power. Worth benchmarking before spending
   money on either Coral or Hailo.
3. **Three drives plus USB Coral**, accepting the shared-bus limit — only if the third drive is
   genuinely required.

Note also that Frigate's own hardware documentation now states the Coral is *not recommended for new
installations* except in low-power deployments, pointing users at Hailo-8 or OpenVINO instead. The
low-power exception does arguably apply to an off-grid build, so Coral is defensible here — but it
should be a deliberate choice, not an inherited one, and "Dual Coral AI" in the repository
description is currently a hardware commitment made before the benchmark.

## Major findings

### M1. The storage architecture contradicts itself

The storage table assigns roles per drive (NVMe = active recordings, SATA = archive/redundancy),
which describes a tiered layout. The later section then selects "RAID 5 for 8 TB usable capacity,"
which requires striping all three drives into one array and destroys the tiering. The two designs
are mutually exclusive and the README asserts both.

RAID 5 across an NVMe drive and two SATA SSDs also runs the whole array at SATA speed and adds
read-modify-write parity amplification on a write-heavy surveillance workload. Pick one:

- **Tiered:** NVMe for hot recordings + Frigate database, SATA pair for archive. Simple, fast, and
  matches how Frigate actually writes data.
- **Single pooled array:** three matched SATA-class drives in RAID 5 or a ZFS raidz1, with the
  performance and rebuild characteristics that implies.

Related: the recommendation to "configure HDD spin-down for inactive periods" is meaningless in an
all-SSD build, and the 8 TB usable target is roughly double the 1.8–4.2 TB the retention estimates
require.

### M2. The Frigate configuration snippet will not load on current Frigate

The snippet in the README is written against a Frigate schema that is several releases out of date,
and one block never existed.

- **`ptz: auto:` is not a Frigate key.** Autotracking is configured per camera under
  `cameras.<name>.onvif.autotracking`, with fields `enabled`, `calibrate_on_startup`, `zooming`,
  `zoom_factor`, `track`, `required_zones`, `return_preset`, `timeout`, and `movement_weights`. The
  `mode: on_event`, `position: home`, and `smooth: true` fields do not exist.
- **`record.retain.default` and `record.events.retain.default` are superseded.** Current Frigate
  uses `record.continuous.days`, `record.motion.days`, `record.alerts.retain.days`, and
  `record.detections.retain.days`.
- **`detect` is disabled by default as of 0.16** and must be explicitly enabled.
- **`return_preset` must name a preset that exists in each camera's firmware**, so PTZ presets are a
  per-camera provisioning step, not a config-file-only change.

A corrected form of the same intent:

```yaml
detect:
  enabled: true
  fps: 5

motion:
  threshold: 50
  contour_area: 40

objects:
  track:
    - person
    - car
  filters:
    person:
      min_score: 0.7
    car:
      min_score: 0.6

record:
  enabled: true
  continuous:
    days: 0
  motion:
    days: 7
  alerts:
    retain:
      days: 10
  detections:
    retain:
      days: 10

cameras:
  driveway_ptz:
    onvif:
      host: 192.168.20.31
      port: 8000
      user: "{FRIGATE_ONVIF_USER}"
      password: "{FRIGATE_ONVIF_PASSWORD}"
      autotracking:
        enabled: true
        calibrate_on_startup: true   # set false after the first calibration run
        zooming: disabled
        track:
          - person
        required_zones:
          - driveway_approach
        return_preset: home
        timeout: 30
```

This should be validated in CI against the schema Frigate publishes at
`/api/config/schema.json` rather than trusted by inspection.

### M3. "Motion tracking: auto-tracking enabled on all cameras" is not achievable

Frigate autotracking requires a PTZ camera that supports ONVIF relative movement within the field of
view (`RelativePanTiltTranslationSpace` containing a `TranslationSpaceFov` entry). Practical
consequences the design does not reflect:

- Fixed-lens cameras cannot autotrack at all, so "all cameras" can only mean "all PTZ cameras."
- Whole product lines are excluded. No current Reolink PTZ supports the required FOV RelativeMove.
  Dahua "Lite" series models are commonly reported as non-working. Some cameras advertise
  `PTZRelative` in the ONVIF conformance database and still fail in practice.
- Each camera autotracks **one** object at a time, so "multiple cameras track same subject across
  zones" is a Home Assistant orchestration problem, not a Frigate feature.
- **A PTZ that is tracking is not watching its assigned scene.** Slewing to follow one person leaves
  the rest of that camera's coverage area blind for the duration. Autotracking PTZs should overlay
  fixed cameras that hold the scene, not replace them.
- Every autotracking camera needs an individual calibration run (`calibrate_on_startup: true`, then
  back to false), and recalibration whenever `return_preset`, detect `fps`, or zooming changes.

Frigate's documentation also notes that detect fps above ~10 slows the motion estimator, which
conflicts with the README's "tracking FPS 10–15" line.

### M4. The budget is understated by roughly 2–3× before power is even counted

| Line item | README estimate | Realistic 2026 pricing |
| --- | --- | --- |
| Managed 2.5GbE PoE+ switch | $100–200 | $550–720 for a 24-port 2.5G PoE+ (500 W budget); ~$1,400+ for Netgear/Ubiquiti class |
| PTZ cameras (12–20) | $1,200–3,000 ($60–150 each) | $200–500 each for ONVIF PTZs that actually support FOV RelativeMove (Dahua/EmpireTech class) |
| ZimaBoard 2 1664 | $279–409 | $279 crowdfunding / ~$349 retail direct, ~$400 with the NVMe carrier and accessories |

There is no PoE+ 2.5GbE switch anywhere near $100–200. And 20 PTZ cameras at 802.3at can request up
to 510 W, which exceeds the 500 W budget of every mid-tier switch in that price band — the design
needs either a 720 W-class switch, a second switch, or a camera mix that mostly draws 802.3af.

A realistic mains-powered total is closer to $6,000–9,000, and the off-grid power system from B1
adds $5,000–11,000 on top. The README's "minimum viable build: $1,200–1,800" is not reachable with
PTZ cameras at all; it is reachable with fixed-lens cameras, which is another argument for making
the PTZ decision explicitly.

### M5. The N150's capacity for 20 cameras is unvalidated, and the CPU is the likely limit

Object detection runs on the accelerator, but **motion detection and stream decode run on the
host**. Community reports put N100/N150-class hardware comfortably at 8–12 cameras; 20 is at or past
the edge. The accelerator math is the easy part: 20 cameras × 5 fps detect = 100 fps aggregate,
which is exactly a single Coral's ~100 fps ceiling and only reached when every camera has motion
simultaneously.

The README's phased rollout already validates at 12 before expanding to 20, which is the right
instinct. What is missing is the *measurement* — the expansion gate should be a recorded number
(host CPU headroom, detector inference time, detection fps under load), not a judgement call.

Also confirm ffmpeg hardware acceleration is actually engaged on the N150 iGPU (`preset-vaapi` or
the QuickSync preset). Without it, decode alone will saturate four cores well before 12 cameras.

## Minor findings

- **M6 — The README does not render as intended on GitHub.** Every table is tab-separated rather
  than pipe-delimited Markdown, so all ~20 tables display as run-together paragraphs, and the
  network diagram is not in a code fence so its box-drawing characters collapse. The document is
  significantly harder to read than its content deserves. Cheap, high-value fix.
- **M7 — eMMC wear.** The 64 GB eMMC is fine for the OS but should not host Frigate's SQLite
  database, its logs, or `/tmp/cache`. Put the database on the SSD array, mount with `noatime`, and
  keep the recording cache on tmpfs with an explicitly sized `shm_size`.
- **M8 — The network design contradicts itself and over-provisions.** Port 1 for the camera VLAN and
  port 2 for management cannot coexist with "bond both 2.5GbE ports for 5 GbE throughput." The
  bonding is unnecessary regardless: 20 cameras at main-stream plus sub-stream is roughly 100–180
  Mbps, under 8% of a single 2.5GbE link. Keep the two-port split.
- **M9 — Security gaps.** VLAN isolation is listed but the control that actually matters is missing:
  an explicit firewall rule denying the camera VLAN any WAN egress, so cheap cameras cannot phone
  home or pull hostile firmware. Also absent: default-credential rotation, a firmware update policy,
  and local NTP for cameras that need time sync without internet. Conversely, Let's Encrypt
  certificates and 2FA on public endpoints are largely redundant if remote access is exclusively
  through Tailscale or Cloudflare Tunnel — the design lists both approaches without choosing.
- **M10 — SSD endurance is unbudgeted.** At 200–420 GB/day, the array absorbs 73–153 TB of writes per
  year, before RAID 5 parity amplification. Specify drives with TBW ratings above ~1 PB and avoid
  QLC or DRAM-less models, or the "SSDs for low power" decision quietly becomes a replacement-cost
  decision.
- **M11 — Storage estimates are unauditable.** The 120–420 GB/day figures may well be right, but no
  per-camera bitrate, resolution, or motion-hours-per-day assumption is stated, so they cannot be
  checked or adjusted when real cameras are chosen. Show the arithmetic.
- **M12 — No privacy or legal considerations.** Audio recording carries consent requirements in many
  jurisdictions, and camera coverage extending onto neighbouring property or public walkways is
  regulated in some. Worth a short section, and worth deciding before mounting hardware.
- **M13 — Repository hygiene.** No `LICENSE`, no `.gitignore`, no directory structure, no CI. The
  README also still ends with the assistant's closing question from the planning session ("Would you
  like me to create a separate configuration template file..."), which should be removed now that
  the answer is captured in the roadmap.

## What the design gets right

Worth preserving through any rework:

- Motion-triggered recording on a sub-stream at 5 fps, with the main stream reserved for recording,
  is exactly the right Frigate topology and is the single biggest determinant of whether the
  hardware copes.
- Phased rollout with a validation soak before expanding is the correct structure. It needs
  measurable exit criteria, not replacement.
- VLAN segmentation plus tunnel-based remote access with no port forwarding is the right security
  posture.
- Keeping Frigate and Home Assistant configuration in Git — which is what this repository should
  become — is listed as a backup strategy and is the correct one.
- The monitoring table (disk usage, daily write, detection rate, Coral utilisation, PTZ activity
  with warning and critical thresholds) is unusually well specified for a planning document and
  should be implemented close to as written.

## Suggested reading order

1. `docs/decisions.md` — the nine open questions from the README, plus the new ones this review
   raises, each with a recommended default and a note on what it blocks.
2. `docs/path-to-completion.md` — the staged plan from here to a running, documented system.
