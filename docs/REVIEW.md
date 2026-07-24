# Technical Review of the Current Design

Reviewed against the repository state at the time of writing: one `README.md` containing the
March 15, 2026 planning session summary (v3.0), and no other files.

The plan is a solid piece of thinking about surveillance architecture. The problems below are
almost all of one kind: the design was written as a general Frigate deployment plan and then
given the name "off-grid", without the power, cost, and configuration consequences of either
"off-grid" or "current Frigate" being worked through. Nothing here requires abandoning the
approach — but several numbers and config snippets will not survive contact with the hardware.

Severity is about what happens if you build the plan as written:

- **Blocking** — you will spend money on the wrong thing, or the system will not run.
- **Significant** — it will run, but badly, or the estimate is wrong enough to matter.
- **Minor** — worth correcting in the document.

---

## Blocking

### B1. There is no power design, in a project named "off grid"

The repository is `Off_grid_home_security_hub`. The plan's only concession to power is a
"600–1000VA UPS" and some HDD spin-down advice, which is a grid-tied design with ride-through.
An off-grid deployment has to start from a load budget, and this load is not small.

Rough continuous draw for the system as specified (12–20 PTZ cameras, all auto-tracking):

| Load | Estimate |
| --- | --- |
| PTZ cameras (16 × ~14 W avg, IR on at night) | ~225 W |
| PoE delivery loss over copper (~15%) | ~35 W |
| Managed PoE+ switch overhead | ~25 W |
| ZimaBoard 2 + 3 SSDs + 2 Coral | ~30 W |
| **Total** | **~315 W → ~7.5 kWh/day** |

Cold nights with camera heaters running push this past 450 W. Sizing a standalone system for
7.5 kWh/day at four peak sun hours and ~70% end-to-end efficiency needs roughly a **2.7 kW array**
and, for two days of autonomy on LiFePO4 at 80% depth of discharge, roughly **19 kWh of battery**.
That is on the order of $4,600–8,600 in panels, batteries, charge controller and inverter — which
is *larger than the entire IT budget the plan quotes*, and it is absent from the cost summary.

What to do:

- Write the load budget before buying cameras; it is the constraint that drives everything else.
- Cut the load first (see B2) — every watt removed is roughly $15–25 of solar and battery avoided.
- Prefer native DC. The ZimaBoard 2 takes 12 V DC directly and PoE injection is 48 V DC. Running
  the hub off the battery bank without a DC→AC→DC round trip through an inverter saves 10–20% of
  total system energy and removes the inverter's idle draw.
- Budget for the fact that off-grid sites usually have metered or intermittent internet
  (cellular/Starlink). Remote *live viewing* of 4K streams is the single easiest way to blow
  through a data cap; plan for substream-only remote viewing.

### B2. "PTZ with auto-tracking on all 12–20 cameras" is the wrong architecture

The plan specifies PTZ cameras with motion tracking everywhere. This is expensive in four
independent ways — hardware cost, power, mechanical wear, and detection reliability — and Frigate's
own documentation recommends against it in favour of a different pattern.

Frigate's autotracking requires the camera to support ONVIF `RelativePanTiltTranslationSpace`
with a `TranslationSpaceFov` entry. Many cheaper and older PTZs advertise this and do not
actually honour it; Frigate logs an error and disables autotracking. Hikvision PTZs are
specifically called out as frequently unusable because their firmware does not update the ONVIF
`MoveStatus` parameter. A camera at the $60–150/unit implied by the plan's budget is very likely
to be in the "claims support, doesn't work" category. Frigate also autotracks **one object per
camera** — a PTZ that is following someone is not watching anything else.

Frigate documents the "spotter" pattern instead: fixed cameras provide wide, reliable coverage,
and when one detects an object, an automation drives a PTZ to a preset covering that area and
lets it take over tracking. That gives you tracking where it is valuable without paying for it
20 times over.

Recommended: **12–17 fixed turret/bullet cameras + 2–3 PTZs** at the approaches that justify
them. This roughly halves the continuous load (to ~3.5–5 kWh/day), removes most of the mechanical
failure surface, and frees budget to buy PTZs that actually work with autotracking rather than
the cheapest ONVIF domes available.

### B3. The Frigate configuration in the README is not valid for current Frigate

Both config blocks in the README use schemas that no longer exist. Pasting them into a current
Frigate will fail config validation and the process will exit.

**Autotracking.** There is no top-level `ptz:` key in Frigate, and `mode: on_event` and
`smooth: true` are not options. Autotracking is configured per camera under
`cameras.<name>.onvif.autotracking`:

```yaml
cameras:
  driveway_ptz:
    onvif:
      host: 10.20.0.51
      port: 8000
      user: "{FRIGATE_ONVIF_USER}"
      password: "{FRIGATE_ONVIF_PASSWORD}"
      autotracking:
        enabled: true
        calibrate_on_startup: false
        zooming: disabled
        track:
          - person
        required_zones:
          - driveway_approach   # required; a full-frame zone is discouraged
        return_preset: home     # must already exist in the camera firmware
        timeout: 10
```

`required_zones` and `return_preset` are required, the preset must be created in the camera's own
firmware first, and zooming is off by default and described upstream as very experimental.

**Recording.** `record.retain.default` and `record.events` were replaced by
`continuous` / `motion` / `alerts` / `detections`. The plan's stated intent — motion-triggered
recording only, 7–10 day rolling retention — is expressed today as:

```yaml
record:
  enabled: true
  continuous:
    days: 0
  motion:
    days: 3
  alerts:
    retain:
      days: 10
      mode: motion
  detections:
    retain:
      days: 10
      mode: motion
```

Note that the README's `record.retain.default: 7` would have done the opposite of what the plan
says it wants: it retains *all* footage for 7 days, not just motion.

**Tracking frame rate.** The plan specifies "Tracking FPS 10–15 during active tracking". Frigate's
documentation says 5 fps is sufficient for autotracking and that rates above 10 fps *slow down*
the motion estimator and can cause dropped frames. There is also no separate "tracking fps"
setting — `detect.fps` is a per-camera constant. Leave it at 5.

### B4. Committing configuration to this public repository will leak credentials

The plan lists "Configuration Backup: Git repository for Frigate/HA configs" as a $0 win. This
repository is **public**. Frigate and Home Assistant configs contain camera RTSP and ONVIF
passwords, internal IP addressing, and zone geometry that maps out the property's blind spots.

Before any config lands here: use Frigate's `{ENV_VAR}` substitution for every credential, keep
the real values in an untracked `.env`, commit only `.env.example`, add a `.gitignore`, and add a
secret-scanning step to CI. If the intent is to back up *real* configs rather than templates, that
belongs in a private repository.

---

## Significant

### S1. The storage plan contradicts itself, and RAID 5 is the wrong answer

The Storage Architecture table assigns the NVMe to active recordings and the two SATA SSDs to
archive. The Storage Configuration section then selects RAID 5 across all three for 8 TB usable.
These are mutually exclusive: RAID 5 stripes the NVMe together with the SATA SSDs, so every write
runs at SATA speed plus parity, the tiering disappears, and the NVMe becomes a single point of
failure for the whole array. The plan's own cost-optimization section then recommends replacing a
SATA SSD with an HDD, which contradicts the RAID 5 selection a third time.

Also worth noting: the retention requirement (1.8–3.0 TB for the mixed 16-camera case) **fits on
the 4 TB NVMe by itself**. The parity capacity is not needed for the stated retention target.

Recommended: NVMe alone for the live recording store, the two SATA devices mirrored (RAID 1) as a
separate archive and backup target for exported clips, the Frigate database, and configuration.
That preserves the tiering, keeps a real second copy of anything worth keeping, and survives the
loss of any one device without a rebuild that saturates the array.

Two related points:

- **Put Frigate's cache on tmpfs.** Frigate writes every segment to `/tmp/cache` before deciding
  whether to keep it. Backing that with RAM (1–2 GB) removes a large amount of pointless SSD write
  amplification. Budget it against the 16 GB of system RAM.
- **Buy TLC with DRAM, not QLC.** At ~250 GB/day, a 4 TB TLC drive (~2,400 TBW) lasts decades; a
  4 TB DRAM-less QLC drive can be an order of magnitude worse, and surveillance is a pure
  sustained-write workload.

### S2. ZFS/btrfs deduplication will not work on this hardware and would not help anyway

The plan lists "Deduplication — ZFS or btrfs for snapshot dedup — 10–20% additional space savings".
Video segments are already entropy-dense and effectively never contain duplicate blocks, so the
saving is near zero. Worse, ZFS dedup needs roughly 1–5 GB of RAM per TB of pooled data; on 8 TB
that is potentially more RAM than this board has in total, competing with Frigate and the ARC.

Recommended: ext4 or XFS on mdadm, or ZFS with dedup off and `zfs_arc_max` explicitly capped so
the ARC cannot starve Frigate.

### S3. Hardware video decoding is missing, and it is the difference between working and not

Nothing in the plan mentions `hwaccel_args`. The N150 has 24 EUs of Intel graphics with Quick Sync,
and Frigate's own FAQ is explicit that a Coral does not help with decoding — decode is pure CPU
work unless offloaded. Decoding 16–20 substreams on four Twin Lake cores without Quick Sync will
saturate the CPU and cause dropped frames.

Set `ffmpeg.hwaccel_args: preset-vaapi` (or the Quick Sync preset) globally, and confirm
`/dev/dri/renderD128` is passed into the container. This is the single highest-value omission in
the software plan.

Related: the plan's "enable H.265 encoding" line is ambiguous. Frigate never re-encodes recordings
— it copies the stream — so H.265 must be selected **in the camera's own firmware**. Host-side
re-encoding of 20 streams on an N150 is not possible. Also note H.265 recordings only play back in
Chrome 108+, Edge and Safari, and Frigate has an `apple_compatibility` option for Safari issues.

### S4. The cost summary is understated by roughly $1,500–3,000, before the power system

Three lines are materially wrong:

| Line item | Plan | Reality | Note |
| --- | --- | --- | --- |
| Managed 2.5GbE PoE+ switch | $100–200 | $500–900 for 24-port 2.5G PoE+ | 8-port 2.5G PoE+ managed alone is ~$180–250 |
| PTZ cameras (12–20) | $1,200–3,000 | $150–350/unit for units that meet the stated spec | $2,400–5,600 for 16 |
| Off-grid power system | absent | $2,500–8,600 depending on load | See B1 |

**The 2.5GbE PoE switch is also simply the wrong product.** IP cameras are 100 Mb or 1 Gb devices;
no camera in this design can use a 2.5G access port. Buy a gigabit PoE+ switch with a 2.5G or 10G
uplink to the ZimaBoard. That is cheaper, draws less power, and loses nothing.

Check the switch's **total PoE budget**, not just its port count: 16 PTZs at PoE+ class 4 can
demand up to 400 W, and most 24-port switches ship with a 200–400 W budget shared across all ports.

### S5. The network diagram and the link aggregation recommendation are incompatible

The architecture uses Port 1 for the camera VLAN and Port 2 for management. The efficiency section
then recommends bonding both ports for "5 GbE throughput". You cannot do both, and LACP does not
give a single stream more than one link's bandwidth anyway — it hashes flows across members.

Keep the two-port split; it is the better design and the reason to buy this board. Twenty
substreams plus twenty main streams is comfortably under 2.5 Gb/s regardless.

### S6. The single PCIe slot and the power/thermal envelope are already committed

The ZimaBoard 2 has exactly one PCIe 3.0 x4 slot (an exposed edge connector, so an NVMe there
needs a riser/adapter), two SATA ports, and two USB 3.1 ports. Consequences the plan should state:

- Using PCIe for the NVMe means **both Corals must be USB**, and they will likely share a USB
  controller. Configure them as separate detectors (`device: usb:0` / `usb:1`).
- The board is **passively cooled**, so the plan's "120 mm PWM case fans" recommendation does not
  apply as written. Sustained four-core load plus iGPU decode plus two Corals in a fanless
  aluminium chassis, inside a hot off-grid enclosure, will thermally throttle. Plan forced air over
  the heatsink and monitor `coretemp`.
- Input is 12 V and 5 A is recommended *with two SATA drives attached*. Three SSDs plus two Corals
  plus a loaded N150 puts you close to that 60 W ceiling. Verify against the real supply.
- The 64 GB eMMC is a low-endurance boot device. Keep Docker's data root, the Frigate database,
  and logs on the NVMe, and cap journald.

### S7. Is a second Coral needed? Probably as headroom, but check the premise

Frigate's guidance: a Coral reporting 10 ms inference tops out at 100 fps of detection. Twenty
cameras at 5 fps is 100 fps — but only if every camera has continuous motion, which never happens.
One Coral is likely sufficient; a second is reasonable insurance and is the right call for a
20-camera build. Two notes:

- Frigate 0.16+ **no longer recommends the Coral for new installations** — except explicitly for
  low-power deployments, which is exactly this one. Keep the Coral; it remains the best
  inferences-per-watt option and that is the binding constraint here.
- Do not plan to fall back to OpenVINO on the iGPU. The iGPU is needed for decode (S3), and
  MobileNetV2 on an N150 iGPU is ~15 ms versus the Coral's ~10 ms at far higher power.

---

## Minor

- **N1. Autotracking timeout.** The plan says 30 s; the Frigate default is 10 s. Either is
  defensible, but 30 s means the PTZ stays off its home preset three times longer after every
  false positive, which matters more when tracking is scanning for a re-acquire.
- **N2. Motion thresholds.** `threshold: 50` / `contour_area: 40` are set globally as if they were
  known-good. They are per-camera and per-scene values; set them with Frigate's motion tuner after
  each camera is aimed, not up front.
- **N3. Cloudflare Tunnel for video.** Listed as co-equal with Tailscale. Cloudflare's
  service-specific terms restrict serving disproportionate non-HTML content such as video through
  the CDN, which is why the Frigate community generally lands on Tailscale/WireGuard for remote
  viewing. For an off-grid site with metered uplink, a point-to-point VPN is also the cheaper
  choice in bandwidth.
- **N4. Frigate has its own authentication.** The plan covers 2FA at the edge but not Frigate's
  built-in user/role authentication, which should be enabled regardless of how remote access is
  fronted.
- **N5. Camera VLAN egress.** "VLAN segmentation" is listed, but the important part — denying the
  camera VLAN any route to the internet, and providing a local NTP server so cameras still get
  time — is not stated. Also disable P2P/cloud/UPnP in every camera's firmware.
- **N6. Monitoring has thresholds but no source.** The maintenance table specifies warning and
  critical levels with no mechanism to measure them. Frigate exposes statistics over its HTTP API
  and recent versions add a Prometheus endpoint; pair that with node_exporter for disk, thermals
  and power.
- **N7. "RAID 5 — 1 drive failure — best balance"** is fine as a statement about RAID, but the
  document never says that RAID is not a backup. With offsite sync listed as a later phase, the
  system spends its entire early life with exactly one copy of everything.
- **N8. Storage estimates carry no stated assumptions.** "~120–180 GB/day for 12 cameras" cannot be
  checked without knowing bitrate, resolution and expected motion hours. Record the assumptions so
  the estimate can be corrected against measured data after the first week.

---

## What the plan gets right

Worth keeping explicitly, because the corrections above should not obscure it:

- The hardware class is well matched: an N150 with Quick Sync, dual NICs for a genuinely isolated
  camera network, and a Coral is the standard, correct shape for a Frigate build of this size.
- Detection on substreams at 5 fps rather than 30 is the most important single tuning decision and
  the plan already made it.
- Motion-triggered retention with separate event retention, motion masks over sky and ground,
  higher night thresholds, and per-camera regions of interest are all the right instincts.
- Isolating cameras on their own VLAN with no port forwarding, reached over a mesh VPN, is the
  correct security posture.
- Choosing the Coral for power efficiency turns out to be well-aligned with the off-grid
  constraint, even though the document never connects those two facts.
- Phasing the rollout — 12 cameras first, soak, then tracking, then expansion — is the right
  sequence and is preserved in the roadmap.

---

## Sources

- Frigate autotracking configuration and camera compatibility:
  <https://docs.frigate.video/configuration/autotracking/>
- Frigate recording retention schema:
  <https://docs.frigate.video/configuration/record/>
- Frigate hardware guidance, Coral throughput, and the decode/detect split:
  <https://docs.frigate.video/frigate/hardware/>
- Frigate command-line config validation:
  <https://docs.frigate.video/configuration/advanced/>
- ZimaBoard 2 1664 specifications (N150, 16 GB LPDDR5x, 64 GB eMMC, 1× PCIe 3.0 x4, 2× SATA 3.0,
  2× USB 3.1, 2× 2.5GbE, passive cooling, 12 V/5 A):
  <https://www.zimaspace.com/products/single-board2-server>
