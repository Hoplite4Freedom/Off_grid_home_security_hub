# Path to Completion

## Where the project stands

The repository contains a design document and nothing else — no configuration, no deployment
definition, no scripts, no license. The design is roughly 70% of the way to a buildable plan for a
grid-tied Frigate installation, and roughly 40% of the way to a buildable plan for an *off-grid*
one, because the power system that the project is named after has not been designed at all.

Two things therefore have to happen, in this order:

1. **Close the design gaps** identified in [REVIEW.md](./REVIEW.md) — chiefly the power budget,
   the fixed-vs-PTZ camera mix, and the storage layout. These change what hardware gets purchased,
   so they cannot be deferred past procurement.
2. **Turn the document into artifacts** — a repository that can rebuild the system from scratch,
   rather than a description of a system that exists only in one person's head and on one eMMC.

The milestones below are ordered by dependency, not by effort. Each has concrete deliverables and
an exit criterion, so it is unambiguous whether it is done.

---

## Guiding principle

Every decision should end up as a file in this repository. The test for "finished" is not "the
cameras work" — it is **"the hub could be rebuilt from this repository and a pile of hardware."**
That test is what makes the difference between a home lab and infrastructure you can rely on when
something fails at 3 a.m. in a shed.

---

## Target repository layout

```
.
├── README.md                     # what this is, how to deploy it
├── LICENSE
├── .gitignore                    # .env, *.key, secrets, media
├── docs/
│   ├── REVIEW.md                 # this review
│   ├── ROADMAP.md                # this file
│   ├── power-budget.md           # load table, solar/battery sizing, measurements
│   ├── network.md                # VLANs, IP plan, firewall rules
│   ├── cameras.md                # inventory: model, location, IP, FOV, purpose
│   ├── decisions/                # one short ADR per resolved open question
│   └── runbooks/                 # disk full, camera offline, restore-from-backup, low battery
├── compose/
│   ├── docker-compose.yml        # frigate, mosquitto, home assistant, monitoring
│   └── .env.example              # every secret, with placeholder values
├── frigate/
│   ├── config.yml                # credentials via {ENV_VAR} only
│   └── includes/                 # per-camera fragments if the main file gets unwieldy
├── homeassistant/
│   ├── packages/                 # spotter→PTZ handoff, notifications, power automations
│   └── automations/
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/dashboards/
├── scripts/
│   ├── bootstrap.sh              # fresh-OS setup: docker, storage, tmpfs cache, tuning
│   ├── storage-setup.sh          # partition, mdadm, fstab
│   └── backup.sh                 # config + database + selected clips → archive tier
└── .github/workflows/ci.yml      # yamllint, frigate config validation, secret scan
```

---

## Milestones

### M0 — Make the repository safe to commit to

Everything else writes files here, so this comes first. The repository is public and will soon
hold configuration for a security system.

**Deliverables**

- `.gitignore` covering `.env`, `*.key`, `*.pem`, `secrets.yaml`, media and database files.
- `.env.example` establishing the convention that every credential is an environment variable.
- A `LICENSE` file (the repository currently has none, so it is "all rights reserved" by default).
- A decision on whether real configuration lives here or in a private mirror.

**Exit criterion** — a reviewer can point at the ignore rules and confirm that no camera password,
internal IP, or zone geometry can reach a public commit by accident.

### M1 — Design the power system

The blocking gap. This determines the camera count, which determines everything downstream.

**Deliverables** — `docs/power-budget.md` containing:

- A per-device load table: cameras (day and night, IR and heater on), PoE conversion losses, switch
  overhead, server, storage. Measured where possible, spec-sheet where not.
- Daily energy in kWh, for both summer and worst-case winter.
- Array and battery sizing from that figure, at the site's actual peak sun hours, with a stated
  autonomy target (days of no sun).
- A decision on DC-coupled versus inverter-fed operation. The ZimaBoard takes 12 V DC natively and
  PoE is 48 V DC; skipping the DC→AC→DC round trip is worth 10–20% of the whole system.
- Low-battery behaviour: what sheds first. A graceful "drop to detection-only on low-priority
  cameras at 30% state of charge" is worth designing now, and it later becomes a Home Assistant
  automation in M6.

**Exit criterion** — the daily kWh figure and the resulting array/battery sizes are written down,
and the total system cost including power is a number the project has agreed to spend.

### M2 — Fix the camera plan and buy hardware

**Deliverables**

- `docs/cameras.md`: every camera as a row — location, purpose, fixed or PTZ, model, resolution,
  main and substream settings, expected motion profile.
- Revised mix per [B2](./REVIEW.md#b2-ptz-with-auto-tracking-on-all-1220-cameras-is-the-wrong-architecture):
  mostly fixed cameras, 2–3 PTZs at approaches that justify them.
- For each PTZ, evidence of Frigate autotracking compatibility *before purchase* — the ONVIF
  Conformant Products Database `PTZRelative` / `PTZRelativePanTilt` features plus a report in
  Frigate's community-maintained working-cameras list. Do not buy a PTZ on the strength of an
  "ONVIF compatible" listing alone.
- Corrected bill of materials with the switch and camera pricing from
  [S4](./REVIEW.md#s4-the-cost-summary-is-understated-by-roughly-15003000-before-the-power-system),
  a gigabit PoE+ switch with a 2.5G uplink instead of a 2.5G access switch, and the switch's total
  PoE watt budget checked against the summed camera draw.

**Exit criterion** — the bill of materials is priced, the PoE budget covers the camera load with
headroom, and every PTZ on the list has been verified compatible rather than assumed compatible.

### M3 — Base platform

**Deliverables**

- `scripts/bootstrap.sh`: OS install (Debian stable or Ubuntu Server LTS), Docker, unattended
  security updates, `/dev/dri` present and permissioned for hardware transcoding.
- `scripts/storage-setup.sh` implementing the layout from
  [S1](./REVIEW.md#s1-the-storage-plan-contradicts-itself-and-raid-5-is-the-wrong-answer):
  NVMe as the live recording store, SATA pair mirrored as the archive tier, ext4 or XFS, `fstab`
  entries, and a tmpfs mount for Frigate's cache.
- Docker data root, the Frigate database and logs relocated off the eMMC; journald capped.
- Thermal mitigation per [S6](./REVIEW.md#s6-the-single-pcie-slot-and-the-powerthermal-envelope-are-already-committed),
  with `coretemp` readings recorded under sustained load.

**Exit criterion** — the board survives a synthetic sustained load without thermal throttling, both
Corals enumerate on USB, and a reboot brings every mount back cleanly.

### M4 — Network

**Deliverables**

- `docs/network.md`: VLAN IDs, subnets, a static IP or DHCP-reservation plan for every camera,
  switch port map, and firewall rules.
- Camera VLAN denied all internet egress, with a local NTP server so cameras keep time
  ([N5](./REVIEW.md#minor)).
- Every camera's firmware hardened: default credentials changed, P2P/cloud/UPnP disabled.
- Port 1 to the camera VLAN, port 2 to management — no bonding
  ([S5](./REVIEW.md#s5-the-network-diagram-and-the-link-aggregation-recommendation-are-incompatible)).

**Exit criterion** — a camera on the camera VLAN cannot reach the internet, can reach the hub, and
holds accurate time; the hub can reach every camera's RTSP and ONVIF endpoints.

### M5 — Frigate, first cameras

The first milestone that produces video.

**Deliverables**

- `compose/docker-compose.yml` for Frigate and Mosquitto, with `/dev/dri` and both Coral devices
  passed through, and `shm_size` sized for the camera count.
- `frigate/config.yml` written against the **current** schema
  ([B3](./REVIEW.md#b3-the-frigate-configuration-in-the-readme-is-not-valid-for-current-frigate)):
  global `hwaccel_args`, detection on substreams at 5 fps, `record.continuous/motion/alerts/
  detections`, two `edgetpu` detectors on `usb:0` and `usb:1`, credentials as `{ENV_VAR}`.
- Frigate's built-in authentication enabled.
- Motion masks over timestamps, overlays, sky and ground; per-camera zones.
- CI job running the upstream validator so a broken config cannot be merged:

```bash
docker run --rm \
  -v $(pwd)/frigate/config.yml:/config/config.yml \
  --entrypoint python3 \
  ghcr.io/blakeblackshear/frigate:stable \
  -u -m frigate --validate-config
```

**Exit criterion** — the first tranche of cameras records on motion, inference speed and detection
fps are within the Coral's budget, CPU stays well clear of saturation with hardware decode
confirmed active, and CI rejects an intentionally broken config.

### M6 — Soak, then tune

This is an observation window, not a task: the tuning data does not exist until the system has
watched the site through several day/night cycles and some weather.

**Deliverables**

- Measured daily write volume compared against the estimates in
  [N8](./REVIEW.md#minor); the retention figures corrected to match reality.
- Per-camera motion thresholds and contour areas tuned with Frigate's motion tuner rather than the
  document's global guesses.
- Night-time IR handling verified; false-positive rate recorded per camera.
- Measured power draw compared against the M1 budget, and the budget corrected.

**Exit criterion** — at least seven consecutive days of data with the false-positive rate low
enough that alerts are worth reading, and storage consumption on a trajectory that fits the
retention target.

### M7 — Tracking and automation

Only after M6, because automating on top of an untuned detector automates the false positives too.

**Deliverables**

- Autotracking enabled on the PTZs, one at a time, each calibrated once
  (`calibrate_on_startup: true`, then set back to `false`). Note that calibration makes the whole
  Frigate UI and every other camera unresponsive for roughly two minutes.
- `homeassistant/packages/` implementing the spotter→PTZ handoff: a fixed camera detects, an
  automation moves the PTZ to the preset covering that approach, Frigate's autotracker takes over
  inside the `required_zones`.
- Chain activation and door/window sensor integration from the original plan.
- Push notifications with a cooldown, so one person walking down the driveway is one alert.
- Low-battery load shedding from M1, wired to the actual battery monitor.

**Exit criterion** — a person walking a known path triggers the handoff, is tracked, and generates
exactly one notification; the PTZ returns to its home preset afterwards.

### M8 — Observability, backup, and the ability to rebuild

The difference between a working system and a maintainable one.

**Deliverables**

- `monitoring/`: Prometheus scraping Frigate's stats endpoint and node_exporter, with Grafana
  dashboards and alerts for every threshold in the README's maintenance table — plus battery state
  of charge and enclosure temperature, which that table does not currently cover.
- `scripts/backup.sh`: Frigate database, configuration, and Home Assistant state to the archive
  tier, then offsite. RAID is not a backup
  ([N7](./REVIEW.md#minor)).
- `docs/runbooks/` for the failures that will actually happen: disk full, camera offline, Coral
  stops enumerating, restore from backup, extended low-solar period.
- **A rehearsed restore.** Rebuild onto spare hardware, or at minimum restore the database and
  config into a fresh container and confirm the system comes up.

**Exit criterion** — an alert fires on a deliberately induced fault, and a restore has been
performed successfully at least once, not merely scripted.

---

## Decision register

The README lists nine open questions with every one marked "Pending". Leaving them all open blocks
procurement. Below is a recommended default for each so the project can move, with the reasoning
compressed; each should become a short ADR in `docs/decisions/` when confirmed or overridden.

| Question | Recommended default | Why |
| --- | --- | --- |
| Physical door/window sensors vs. camera-based AI? | Both — Zigbee contact sensors on entry points | Sensors are ~$15–30, draw almost nothing, and work in darkness and fog when cameras do not |
| Remote access: Tailscale vs. Cloudflare Tunnel? | Tailscale | Cloudflare's terms restrict video through the CDN; a mesh VPN is also cheaper on a metered off-grid uplink |
| Budget for storage expansion? | None initially | 7–10 days of the mixed profile fits on the 4 TB NVMe; expand from measured data after M6 |
| Backup strategy for critical footage? | Local mirror + weekly offsite of alerts only | Full footage offsite is unaffordable on off-grid bandwidth; alert clips are what gets used |
| Home Assistant integration depth? | Full, local-only | It is already required for spotter→PTZ handoff and load shedding; no cloud dependency at an off-grid site |
| PoE switch capacity: 24-port vs. 16-port? | Size by watts, not ports — gigabit PoE+ with a 2.5G uplink | Cameras cannot use 2.5G access ports; the PoE watt budget is the real constraint |
| Offsite backup provider? | Backblaze B2 or Wasabi, alert clips only | Both are cheap at this volume; the constraint is uplink bandwidth, not price |
| PTZ camera brand/model? | Dahua/Amcrest class, verified against Frigate's working list | Frigate's autotracking was developed on Dahua; Hikvision firmware frequently breaks it |
| Motion tracking sensitivity thresholds? | Defer to M6 | These are per-camera, per-scene values that cannot be chosen before the cameras are aimed |

---

## Definition of done

The project is complete when all of the following are true:

- The repository can rebuild the hub from bare hardware: bootstrap, storage, compose, config,
  automations, monitoring.
- No secret has ever been committed, and CI enforces that.
- Every camera is inventoried with its purpose, position, and settings.
- The power system is designed from a measured load, and the system survives a documented
  worst-case low-solar period without data loss.
- Recording, retention, and alerting behave as specified, verified against measured storage and
  detection data rather than estimates.
- Spotter→PTZ handoff works end to end on the PTZs that were verified compatible.
- Alerts fire for every threshold in the maintenance table, and a restore from backup has been
  rehearsed.
- The runbooks are good enough that someone who is not the author could follow them.
