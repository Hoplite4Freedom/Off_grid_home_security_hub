# Path to Completion

Companion to [`technical-review.md`](./technical-review.md). That document says what is wrong with the
current plan; this one says what "finished" means and in what order to get there.

## Definition of done

The project is complete when the deployed system can be rebuilt from this repository. Concretely:

1. Every service runs from committed configuration — no undocumented manual steps on the host.
2. A camera can be added by editing one file and restarting one container.
3. The host can be lost entirely and rebuilt from the repository plus a storage restore, and that restore
   has actually been performed at least once.
4. The operational thresholds in the monitoring table are collected and alert automatically.
5. Secrets live outside the repository and no credential has ever been committed.
6. Every open decision has an owner, a resolution and a recorded rationale.

## Milestone 0 — Freeze scope and power budget

Nothing else can be sized until this is settled, because the off-grid power budget caps the camera count,
and the camera count drives detector load, storage, switch size and cost (finding B1).

- Build a single load model: watts per device class × count → kWh/day → PV array and battery bank →
  cost. Keep it as a small spreadsheet or script in the repo so the numbers can be re-run when the camera
  count changes.
- Choose the operating point where power cost, camera count and total budget intersect. Expect this to
  land below 20 cameras.
- Decide DC-coupled versus inverter-based supply (see B1 — DC-coupling avoids 10–15% conversion loss).
- Resolve the nine open questions (recommended defaults below).
- Produce a bill of materials with real part numbers and current prices, including the lines missing from
  the current budget: PoE cabling, junction boxes, mounts, the PCIe-to-NVMe adapter, enclosure, spares.

**Exit criteria:** camera count and mix frozen; power subsystem specified and costed; BOM totals within
the approved budget; all nine decisions recorded with rationale.

## Milestone 1 — Make the repository the source of truth

Restructure before any hardware arrives, so that bring-up notes land somewhere useful instead of in a
chat log.

```
├── README.md                  # what this is, current status, how to deploy
├── LICENSE
├── .gitignore                 # excludes .env, *.key, secrets.yaml, media/
├── docs/
│   ├── technical-review.md
│   ├── roadmap.md
│   ├── decisions/             # one file per decision, with rationale
│   ├── design/
│   │   └── 2026-03-15-session-notes.md   # the original planning document
│   └── runbooks/
├── compose/
│   ├── docker-compose.yml     # frigate, go2rtc, mosquitto, homeassistant
│   └── .env.example
├── config/
│   ├── frigate/               # config.yml + per-camera includes
│   ├── homeassistant/         # automations, MQTT sensors
│   └── mosquitto/
├── monitoring/                # prometheus, grafana dashboards, alert rules
├── scripts/                   # storage setup, backup, health checks
└── power/                     # load model, PV/battery sizing
```

Alongside the restructure, fix the README's broken tables (L1), move the session notes to
`docs/design/` (L2), and add `LICENSE` and `.gitignore` (L3).

**Exit criteria:** `docker compose config` validates; the Frigate config passes Frigate's own config
check; `git grep` finds no credentials; a new reader can tell from the README what state the project is
in.

## Milestone 2 — Bench bring-up with two cameras

Prove the platform before scaling. Two cameras on a desk, no PTZ, no VLANs yet.

- Install the base OS (Debian stable) and lay out storage per the tiering decision from B2.
- Bring up Frigate, go2rtc and MQTT in Docker with a config that is correct for current Frigate (B3):
  hardware-accelerated decode via VAAPI, `copy` for record streams, two `edgetpu` detectors on `usb:0`
  and `usb:1`, explicit `shm_size`, cache on fast media (M3).
- Measure and record: inference time in milliseconds, detection fps, CPU load, RAM, and **wall power**
  under sustained detection. Wall power feeds straight back into the Milestone 0 model.
- Verify the OpenVINO iGPU fallback works as a degraded mode with the Corals unplugged (M1).

**Exit criteria:** measured inference and power numbers committed to the repo; recordings landing on the
correct tier; `intel_gpu_top` confirming hardware decode is active; the config in git is the config
running on the box.

## Milestone 3 — Network and security baseline

Do this before the camera count grows, because retrofitting VLANs across twenty deployed cameras is
tedious and error-prone.

- Camera VLAN on NIC 1, management on NIC 2; DHCP reservations for every camera.
- **Deny all egress from the camera VLAN** except an internal NTP server (M6). Verify by trying to reach
  the internet from a camera.
- Tailscale or Cloudflare Tunnel for remote access; no inbound port forwards.
- TLS with valid certificates; Frigate's built-in authentication enabled; 2FA at the tunnel.
- Secrets in `.env` / Frigate secrets, excluded from git; document the credential rotation procedure.
- UPS wired to NUT so the host shuts down cleanly on low battery — off-grid, this is also the
  low-state-of-charge shutdown path.

**Exit criteria:** camera VLAN provably cannot reach the internet; remote access works from outside the
network with no port forwarding; a simulated power loss shuts the host down cleanly and it comes back up
unattended.

## Milestone 4 — Scale the fixed-camera fleet

Add cameras in batches of four, measuring after each batch rather than deploying all of them and tuning
afterwards.

- Per batch: mount, reserve IP, add to config, set motion masks (sky, road, foliage, timestamp overlay)
  and zones, then observe.
- Track detection fps against the detector ceiling, storage GB/camera/day, and incremental wall power per
  camera.
- Tune thresholds only with data. Night-time IR needs a different motion threshold than daytime (the
  document's instinct here is right); mask before you raise thresholds.
- Run a 14-day soak at full fixed-camera count.

**Exit criteria:** measured storage per day within 20% of the Milestone 0 model, or the model corrected;
detection fps below 70% of the detector ceiling; false-positive rate low enough that alerts are worth
reading; 14 days with no unplanned restarts.

## Milestone 5 — PTZ and autotracking

Only after the fixed fleet is stable, and only on validated hardware (B4).

- Buy **one** candidate PTZ. Verify ONVIF relative-FOV movement with ONVIF Device Manager before
  ordering more. Frigate reports an error and disables autotracking on unsupported PTZs, and some cameras
  claim support they do not honor.
- Configure `cameras.<name>.onvif.autotracking` with a named firmware preset as `return_preset`, a
  required zone that is not the full frame, and a motion mask over the timestamp overlay.
- Run calibration once, then set `calibrate_on_startup: false`. Start with `zooming: disabled`.
- Observe for a week: does it return to preset, does it lose objects, does it cycle on wind or shadows?
- Only then order the remaining PTZs.

**Exit criteria:** autotracking works reliably on the validated model; PTZ returns to preset every time;
no runaway movement or rapid cycling; PTZ movement count per hour within the monitoring threshold.

## Milestone 6 — Automation and integration

- Home Assistant with the Frigate integration over MQTT.
- Chain activation: fixed spotter camera detects a person → automation moves the PTZ to the covering
  preset → Frigate autotracking takes over. This is Frigate's documented pattern and is the correct way
  to get the coverage the original plan wanted from twenty tracking cameras.
- Door/window sensors, notifications with snapshots, and any geofencing or arming logic.
- Keep recording logic in Frigate; use Home Assistant for orchestration and notification only, so a Home
  Assistant outage never costs footage.

**Exit criteria:** automations committed to the repo; each scenario tested end to end and documented;
notifications arrive with a useful snapshot in under a few seconds.

## Milestone 7 — Backup, disaster recovery and monitoring

- 3-2-1 for what actually matters: configuration (git), the Frigate database, and alert clips. Bulk
  continuous footage is generally not worth offsite bandwidth.
- Offsite copy — an object store for alert clips, plus a rotated offline drive. For a security recorder,
  an offsite copy matters more than in-chassis parity, because chassis theft is a realistic threat (B2).
- Filesystem snapshots with automated pruning, if the storage layout supports them.
- Prometheus scraping Frigate's `/api/stats`, Grafana dashboards, and alert rules implementing the
  warning/critical thresholds from the monitoring table (M8): disk usage, daily write volume, detection
  rate, detector utilization, PTZ activity, camera offline, and — off-grid — battery state of charge and
  PV input.

**Exit criteria:** a restore performed from scratch onto clean storage and documented; each alert rule
fired at least once against a synthetic breach; battery and solar telemetry visible on the same dashboard
as the camera metrics.

## Milestone 8 — Operations handover

- Runbooks for the predictable failures: disk full, camera offline, Coral dropped off the USB bus,
  extended low-solar period, host will not boot, Frigate upgrade, retention change.
- A network diagram and IP inventory that match reality.
- A quarterly maintenance checklist: clean IR housings, check mounts, review retention and false-positive
  rates, apply camera firmware updates, test the restore.

**Exit criteria:** someone other than the builder can resolve a camera outage using only the repository.

## Recommended defaults for the open decisions

These are defaults to disagree with, not conclusions. Recording a default lets Milestone 0 close by
exception rather than stalling on nine parallel questions.

| Question | Recommended default | Why |
| --- | --- | --- |
| Physical sensors vs camera-based AI | Zigbee contact sensors as primary, camera AI as corroboration | Cheap, no false positives, works in darkness, and independent of the camera path |
| Tailscale vs Cloudflare Tunnel | Tailscale | Simpler, nothing exposed publicly, works behind CGNAT — likely relevant for an off-grid site on cellular |
| Storage expansion budget | Defer until Milestone 4 measurements | The 10–21 GB/camera/day estimate is unvalidated (M5) |
| Backup strategy | Configs in git, alert clips + database to object storage, rotated offline drive | Matches the actual threat model; bulk footage offsite is rarely worth the bandwidth |
| Home Assistant depth | Orchestration and notification only; recording stays in Frigate | A Home Assistant outage should never cost footage |
| PoE switch capacity | Size by PoE watt budget, not port count or speed; 1GbE with 2.5G uplinks | ~200 Mbps aggregate does not need 2.5GbE to the edge; saves several hundred dollars and idle watts (B5) |
| Offsite backup provider | Any S3-compatible object store with a restic or rclone workflow | Provider choice is reversible; the workflow is what needs testing |
| PTZ brand/model | Buy one Dahua/EmpireTech unit from the Frigate autotracking compatibility list and validate before ordering more | Autotracking support is the binding constraint, not price (B4) |
| Motion tracking thresholds | Start at Frigate defaults; mask before tuning; separate day/night motion thresholds | Thresholds tuned before masks are set will just hide the symptom |

## Risk register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Off-grid power cost forces a redesign after hardware is bought | High | Milestone 0 gates all purchasing |
| PTZs arrive without working ONVIF relative-FOV movement | High | Validate one unit before ordering the fleet (B4) |
| Coral supply or long-term support ends | Medium | OpenVINO iGPU fallback configured and tested at Milestone 2; Hailo-8 M.2 possible if the PCIe slot is freed |
| Storage fills faster than modelled | Medium | Measure at Milestone 4 before buying the final tier; Frigate's emergency cleanup is a backstop, not a plan |
| USB Coral drops off the bus under sustained load | Medium | Monitor detector restarts; powered hub and extension cable away from chassis heat (M1) |
| Fanless chassis thermal throttling with 20 cameras | Medium | Log package temperature from Milestone 2; the board has a fan header if needed |
| Credentials committed to a public repository | High | `.gitignore` and secrets handling in place from Milestone 1, before any real config is written |
