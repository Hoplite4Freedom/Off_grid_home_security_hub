# Path to Completion

The project is at "design captured in prose." This is the route from there to a running, documented,
recoverable system whose behaviour is known rather than assumed.

The organising principle: **every stage ends with a measurement or an artifact committed to this
repository, not with an opinion.** The README's phased rollout already has the right shape — what it
lacks is exit criteria you can fail. Each stage below has them.

Stages 0–2 are largely independent and can proceed in parallel. From Stage 3 onward the sequence is
mostly forced by physical dependencies.

---

## Definition of done

The project is complete when all of the following are true:

- A documented, reproducible build: a person with the BOM and this repository can rebuild the system
  from bare hardware without recovering any knowledge from someone's memory.
- Measured, not estimated, figures recorded for: daily power consumption, daily storage growth, host
  CPU headroom, detector inference time, and false-positive rate per camera.
- A restore from backup has actually been performed and documented.
- Alerts reach the operator both with the WAN link up and with the WAN link down.
- The system has run unattended for 30 days with monitoring in place and no unplanned intervention.

---

## Stage 0 — Make the repository a project

*Goal: the repository can hold engineering work.*

- Fix the README's Markdown so it renders (finding M6): convert the ~20 tab-separated tables to
  pipe-delimited Markdown, fence the network diagram, and remove the trailing planning-session
  question.
- Add `LICENSE` and `.gitignore` (exclude secrets, `*.db`, recordings, local overrides).
- Create the directory structure the later stages fill in:

```
docs/                  design notes, runbooks, decisions, this plan
compose/               docker-compose stack (frigate, mosquitto, home assistant, monitoring)
frigate/               config.yml plus per-camera includes
homeassistant/         automations, scripts, dashboards
network/               VLAN plan, IP inventory, firewall rules
power/                 load budget, sizing calculations, load-shedding policy
scripts/               storage setup, backup, health checks, ONVIF capability test
.github/workflows/     CI
```

- Move the nine open questions out of the README and into `docs/decisions.md` (already drafted), so
  the README describes the design and the register tracks what is undecided.
- Record secrets handling: a `.env` file excluded from Git, referenced from Frigate config via the
  `{FRIGATE_*}` substitution syntax. No credentials in committed YAML, ever.

**Exit criteria:** README renders correctly on GitHub; repository structure exists; no credentials
anywhere in history.

---

## Stage 1 — Resolve the blocking decisions

*Goal: stop the bill of materials from being a guess.*

Work through `docs/decisions.md` in order. D1 through D5 gate hardware purchasing and each has a
recommended default, so this is a review-and-ratify exercise rather than an open-ended one. Record
the date and reasoning for each acceptance — the reasoning is what future-you will need.

**Exit criteria:** D1–D5 marked Accepted; a bill of materials priced against real 2026 listings
rather than the README's estimates.

---

## Stage 2 — Power system design (the missing subsystem)

*Goal: know what the system costs in watt-hours before buying anything that consumes them.*

This stage exists because of finding B1 and has no counterpart in the README.

- Build a per-device load budget in `power/load-budget.md`: device, quantity, idle draw, active
  draw, duty cycle, daily Wh. Include the WAN link, which at 45–75 W for Starlink can rival the
  entire compute stack.
- Size generation and storage from that budget using site-specific peak-sun-hours (not the generic
  4 h/day used in the review's estimate) and worst-month rather than average insolation.
- Decide AC-coupled versus DC-coupled. Much of this equipment is natively 12 V (ZimaBoard) or 48 V
  (PoE), so a DC-native design can avoid 10–15% inverter losses — meaningful when the whole budget
  is a few kWh/day.
- Define the **load-shedding policy** as an explicit table: battery state-of-charge thresholds
  mapped to system behaviour (all cameras → high-priority cameras only → detection fps reduced →
  recording only → safe shutdown). This is what Home Assistant will implement in Stage 9.
- Specify battery monitoring that Home Assistant can read (most commonly a BMS exposing Modbus or a
  shunt-based monitor with an MQTT bridge).

**Exit criteria:** daily Wh budget with 20% margin; generation and storage sized against worst-month
insolation; load-shedding thresholds defined; power BOM priced.

---

## Stage 3 — Bench bring-up

*Goal: the software stack runs and its performance is measured, before anything is mounted on a wall.*

Two to four cameras on a desk. No cabling, no roof work, no commitment.

- Install the base OS on eMMC (Debian or Ubuntu Server), with `noatime` and log2ram to limit eMMC
  wear (finding M7).
- Bring up the Docker Compose stack: Frigate, Mosquitto, Home Assistant. Commit the compose file.
- Write a valid `frigate/config.yml` against the **current** schema — the README's snippet will not
  load (finding M2). Confirm hardware-accelerated decode is actually engaged on the N150 iGPU, not
  silently falling back to CPU.
- **Benchmark the detector options** to settle D4: run OpenVINO on the iGPU first and record
  inference time and host CPU. Only buy an accelerator if the numbers fall short.
- Add CI (`.github/workflows/`): YAML lint, plus Frigate config validation against the schema
  published at `/api/config/schema.json`. This is what stops finding M2 from recurring.

**Exit criteria:** stack runs from `docker compose up`; config passes CI validation; inference time,
host CPU per camera, and hardware-decode confirmation recorded in `docs/benchmarks.md`.

---

## Stage 4 — Storage and data durability

*Goal: recordings survive a drive failure and a total loss of the machine.*

- Create the array per the D5 decision; script it in `scripts/` rather than doing it by hand, so it
  is reproducible.
- Relocate Frigate's database off the eMMC; size `/tmp/cache` as tmpfs with an explicit `shm_size`.
- Apply the retention configuration using the current schema keys (`record.continuous.days`,
  `record.motion.days`, `record.alerts.retain.days`, `record.detections.retain.days`).
- Implement the D9 backup tiers: configuration to Git, weekly `rsync` of the alert-clip archive to
  external USB, optional offsite for flagged clips.
- **Rehearse a restore.** Wipe a test target, restore from backup, verify Frigate starts with its
  history intact. Document the procedure in `docs/runbook-restore.md`.
- Simulate a drive failure on the bench array and document the rebuild procedure and its duration.

**Exit criteria:** restore rehearsal completed and documented; drive-failure rebuild documented;
retention policy verified by observing actual file deletion, not by reading the config.

---

## Stage 5 — Network build

*Goal: cameras are isolated, powered, and inventoried.*

- Implement the VLAN plan: camera VLAN, management VLAN, IoT VLAN if Zigbee gear warrants one.
- **Add the explicit deny rule for camera-VLAN WAN egress** (finding M9). This is the control that
  actually matters and the README omits it. Verify from a camera that the internet is unreachable.
- Keep the two-port split (camera VLAN on one 2.5GbE port, management on the other). Skip link
  aggregation — the traffic is under 8% of one link (finding M8).
- Verify the switch's PoE budget against the real camera draw with 30% headroom (finding M4).
- Rotate all camera default credentials; set up local NTP so cameras keep time without internet.
- Commit an IP inventory and a network diagram to `network/`.
- Set up Tailscale (or the D6 alternative) and verify remote access with no ports forwarded.

**Exit criteria:** camera VLAN provably cannot reach the WAN; PoE draw measured against budget; IP
inventory committed; remote access works from outside the network with zero inbound firewall rules.

---

## Stage 6 — Deploy the first 12 cameras and soak

*Goal: replace every estimate in the README with a measurement.*

- Mount and cable the first 12 cameras per the D2/D3 decision.
- Configure motion masks and zones per camera. This is the highest-leverage tuning available and
  directly reduces both false positives and detector load.
- Apply the night-vision mitigations the README already identifies (mask sky and ground, raise the
  night threshold, clean IR housings, adjust angles to reduce IR bounce).
- **Soak for two weeks.** Record daily: GB written, detection fps, host CPU, inference time, false
  positives per camera per day, and actual power consumption against the Stage 2 budget.
- Tune one variable at a time and commit each change, so the tuning history is recoverable.

**Exit criteria:** 14 days of recorded metrics in the repository; measured GB/day within the storage
budget; false-positive rate at a level the operator will not learn to ignore; measured power draw
within the Stage 2 budget.

---

## Stage 7 — Autotracking on the PTZs that support it

*Goal: autotracking works on the two to four cameras where it adds value, and nowhere else.*

Scoped by finding M3 — this is not a system-wide feature.

- Run the community ONVIF capability script against each PTZ before relying on it. Some cameras
  advertise `PTZRelative` and still fail.
- Create the named `home` preset in each camera's firmware; `return_preset` refers to a
  firmware-side preset, not a Frigate-side one.
- Calibrate each camera individually: `calibrate_on_startup: true`, one restart, then set it back to
  false so the generated `movement_weights` are not overwritten. Recalibrate after any change to
  `return_preset`, detect `fps`, or zooming.
- Define `required_zones` per camera — deliberately not a full-frame zone, which the Frigate
  documentation warns against.
- Leave `zooming: disabled` initially. It is documented as experimental and CPU-hungry.
- Confirm the fixed cameras cover each PTZ's scene while that PTZ is slewing away from it.

**Exit criteria:** `movement_weights` committed per camera; a documented tracking test (walk the
approach, confirm acquisition, tracking, and return to preset); confirmation that no coverage gap
opens while a PTZ is tracking.

---

## Stage 8 — Expansion gate

*Goal: decide on 20 cameras with numbers instead of optimism.*

Expand beyond 12 only if all four measurements from Stage 6 show **at least 30% headroom**:

| Resource | Gate |
| --- | --- |
| Host CPU | ≥30% idle at peak, with hardware decode confirmed active |
| Detector | Peak detection fps ≤70% of the detector's ceiling (1000 / inference ms) |
| Storage | Measured GB/day × retention days ≤70% of usable array capacity |
| Power | Measured daily Wh ≤70% of worst-month generation |

If any gate fails, the correct response is to fix the constraint or stop at 12 — not to expand and
hope. The most common fix is better motion masks, which costs nothing.

**Exit criteria:** the four measurements recorded and the expansion decision documented either way.

---

## Stage 9 — Automation and alerting

*Goal: the system tells the operator what matters, including when the internet is gone.*

- Implement Home Assistant automations over MQTT per D10: chain camera activation (front doorbell
  motion → indoor entry camera), contact-sensor correlation, notification routing.
- Add the Zigbee contact sensors from D7 and their coordinator.
- **Build the offline alert path** (finding B1). Every notification route in the README depends on
  the WAN link. Add a local annunciator — siren, indoor display, or local-network push — that fires
  with no internet at all, and test it with the WAN physically disconnected.
- Implement the Stage 2 load-shedding policy as Home Assistant automations driven by battery state
  of charge.
- Tune alerting to the operator's actual tolerance. An alert stream people ignore is worse than no
  alert stream, because it produces false confidence.

**Exit criteria:** chain activation demonstrated end to end; alert delivered with WAN up *and* local
alert delivered with WAN down; load shedding demonstrated by simulating a low state-of-charge
reading.

---

## Stage 10 — Observability and runbooks

*Goal: the system's health is visible and its failures have written responses.*

- Implement the README's monitoring table close to as written — it is unusually well specified.
  Disk usage (warn 80% / critical 90%), daily write (200/300 GB), detection rate (50/100 per hour),
  detector utilisation (70%/85%), PTZ activity (50/100 events per hour). Add battery state of
  charge and generation-versus-consumption to that table.
- Stand up dashboards (Prometheus and Grafana, or Home Assistant dashboards if that is sufficient —
  prefer the lighter option, since every watt is budgeted).
- Write runbooks in `docs/`: drive failure, camera offline, detector failure, array full, WAN down,
  low battery, Frigate upgrade, restore from backup.
- Document the upgrade procedure specifically. Frigate has a history of breaking config changes
  between minor releases (0.16 disabled detection by default and moved add-on config paths), so
  pin versions and read release notes before upgrading.

**Exit criteria:** every threshold in the monitoring table actually fires an alert when crossed
(test by simulation); a runbook exists for each entry above.

---

## Stage 11 — Resilience and handover

*Goal: the system survives its operator being unavailable.*

- Complete the offsite backup tier from D9 if not already done.
- Full disaster-recovery rehearsal: rebuild from bare hardware using only this repository, and time
  it. Whatever knowledge turns out to be missing is the documentation gap.
- Write the maintenance calendar: IR housing cleaning, firmware updates, battery health checks,
  array scrubs, backup verification, credential rotation.
- Address the privacy and legal items from finding M12 — audio recording consent and coverage of
  neighbouring property — before the system is considered operational.
- Run 30 days unattended with monitoring active.

**Exit criteria:** bare-metal rebuild completed from documentation alone; 30-day unattended run with
no unplanned intervention.

---

## Critical path

Most stages are gated by physical or logical dependencies, but three items block disproportionately
and should be started first:

1. **D1, the power architecture decision.** Everything downstream — camera type, camera count,
   accelerator, storage medium, WAN link — is a function of the power budget. Deciding it late means
   re-deciding everything else.
2. **The detector benchmark in Stage 3.** It resolves D4, which resolves the PCIe slot conflict
   (B2), which resolves the storage layout (D5), which resolves the BOM. It costs nothing but time
   and can be run on a bench with two cameras.
3. **Buying one PTZ before buying several.** D11's FOV RelativeMove requirement is the kind of
   constraint that turns into an expensive pile of returned hardware if it is verified after
   purchase rather than before.

## Highest-risk assumptions

Ranked by cost if wrong:

| Assumption | Risk if wrong | Cheapest way to test it |
| --- | --- | --- |
| Off-grid power can support this load | Project is not viable as scoped | Stage 2 load budget — desk exercise, no cost |
| N150 handles 12–20 cameras | Hardware replacement | Stage 3 bench benchmark with 2–4 cameras |
| PTZs support FOV RelativeMove | Cameras unusable for autotracking | Buy one, run the ONVIF capability script |
| Storage estimates (120–420 GB/day) | Array undersized or over-bought | Stage 6 soak, two weeks of real data |
| Budget of $2,300–4,650 | Project stalls mid-build | Stage 1 BOM priced against real listings |
