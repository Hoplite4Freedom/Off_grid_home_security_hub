# Decision Register

The README lists nine open questions with the status "Pending" and no recommended answers. This file
restates them with a recommended default, the reason, and what each one blocks — so that work can
start on the recommendation and only stop if the recommendation is rejected.

Decisions are ordered by how much downstream work they gate. `D1`–`D4` should be settled before any
hardware is purchased, because they determine the bill of materials.

Status values: **Open** (needs an answer), **Proposed** (recommendation stands unless rejected),
**Accepted** (decided; record the date and the reasoning), **Superseded**.

---

## D1. Power architecture: what does "off grid" actually mean here?

**Status:** Open — blocks everything

This is not in the README's question list, which is itself the finding. The repository name promises
off-grid operation and the design assumes mains power with a UPS.

Pick one:

- **(a) Fully off-grid** — solar plus battery, no utility connection. Requires the full load budget,
  generation and storage sizing, and a load-shedding policy driven by battery state of charge.
- **(b) Grid-tied with extended autonomy** — mains normally, battery carries multi-day outages.
  Substantially cheaper; the sizing exercise is similar but the array can be smaller.
- **(c) Grid-tied with a conventional UPS** — minutes of runtime, clean shutdown only. This is what
  the README currently describes, and it does not match the repository name.

**Recommendation:** decide explicitly and rename the repository if the answer is (c). If the answer
is (a) or (b), the power system is the first engineering deliverable, not the last.

**Blocks:** D2 (camera type), D3 (camera count), accelerator choice, storage medium, WAN link choice,
and the entire budget.

---

## D2. Fixed-lens or PTZ cameras, and how many of each?

**Status:** Proposed

The README assumes 12–20 PTZ cameras with autotracking on all of them. Review findings M3 and B1
show this is both technically unachievable and the dominant power and cost driver: PTZs draw roughly
double a fixed turret, cost $200–500 each against $60–150, and a PTZ that is tracking one subject
stops covering its assigned scene.

**Recommendation:** a **hybrid**. Fixed turrets for scene coverage on every approach, plus **2–4
PTZs** at the highest-value vantage points (driveway, main approach) where following a subject adds
information that a fixed camera cannot. Autotracking is enabled only on those PTZs.

**Blocks:** power budget, PoE switch sizing, camera BOM, autotracking scope.

---

## D3. Camera count: 12, 16, or 20?

**Status:** Proposed

**Recommendation:** design the network and power for 20, deploy 12, and gate expansion on measured
headroom (see the Stage 8 gate in the roadmap). Cabling and switch ports are expensive to retrofit;
cameras are not. The README's phased plan already says this — it just needs numeric exit criteria.

**Blocks:** switch port count, PoE budget, array sizing.

---

## D4. Object detector: Coral, Hailo-8, or the N150 iGPU?

**Status:** Open — benchmark first

Frigate no longer recommends Coral for new installations except in low-power deployments (which
this arguably is). Meanwhile the single PCIe slot cannot host both an NVMe drive and an M.2
accelerator (finding B2).

**Recommendation:** **benchmark OpenVINO on the N150 iGPU before buying anything.** At roughly 15 ms
inference (~67 detections/sec) it likely covers 12 cameras at 5 fps detect, costs nothing, adds no
power draw, and leaves the PCIe slot free. Buy a Coral or Hailo only if the benchmark falls short.

If an accelerator is needed: Hailo-8 M.2 (~7 ms) is faster and is what Frigate now recommends; Coral
M.2 (~10 ms) is lower power and better supported on the older model line. Prefer M.2 in the PCIe
slot over USB in either case — two USB Corals share one host controller and the second often adds
little.

**Blocks:** PCIe slot allocation, therefore drive count, therefore D5.

---

## D5. Storage layout: tiered or pooled?

**Status:** Proposed

Finding M1: the README specifies both and they are incompatible.

**Recommendation:** **two 4 TB SATA SSDs, mirrored, with the PCIe slot left free** for the
accelerator or a future NIC. 4 TB usable comfortably covers the 1.8–4.2 TB that 10-day retention
actually needs, mirroring survives a drive failure without RAID 5 parity write amplification, and
dropping the third drive saves cost and a few watts.

If the third drive is kept, use tiering (NVMe hot + SATA archive), not a three-drive RAID 5 spanning
mismatched interfaces.

Regardless of layout: Frigate's database and `/tmp/cache` go on the SSD array or tmpfs, never the
eMMC (finding M7), and drives should be specified above ~1 PB TBW (finding M10).

**Blocks:** BOM, array setup scripts, retention configuration.

---

## D6. Remote access: Tailscale or Cloudflare Tunnel?

**Status:** Proposed *(README question 2)*

**Recommendation:** **Tailscale.** It is a private overlay with no public endpoint at all, it handles
the "administrator on a phone" case cleanly, and its bandwidth is peer-to-peer rather than proxied —
which matters when the off-grid WAN link is metered cellular. Cloudflare Tunnel is the better answer
only if untrusted third parties need browser access without installing anything.

Consequence if accepted: the Let's Encrypt and public-endpoint-2FA line items in the README become
unnecessary. Use Frigate's built-in authentication behind the tunnel instead.

**Blocks:** network build, alerting path, security documentation.

---

## D7. Door and window sensing: physical sensors or camera-based AI?

**Status:** Proposed *(README question 1)*

**Recommendation:** **physical Zigbee contact sensors** ($15–30 each). They are definitive rather
than probabilistic, draw effectively no power, work in complete darkness, work when the camera view
is obstructed, and integrate with Home Assistant in minutes. Camera-based inference for a binary
open/closed state spends detection budget on something a $20 sensor answers perfectly.

**Blocks:** Home Assistant automation design, Zigbee coordinator purchase.

---

## D8. PoE switch: capacity and PoE budget

**Status:** Open *(README question 6)*

Depends on D2 and D3. Real constraints from the review: a 24-port 2.5GbE PoE+ switch is $550–720,
not $100–200, and its typical 500 W PoE budget is *below* what 20 × 802.3at cameras can request.

**Recommendation:** size the PoE budget from the actual camera BOM with 30% headroom once D2 lands.
If the answer is mostly fixed turrets, gigabit PoE+ is entirely sufficient for camera traffic and
much cheaper — 2.5GbE is only needed on the uplink to the ZimaBoard, if at all. Do not buy 2.5GbE to
every camera port out of habit; the traffic is under 8% of a single 2.5G link.

**Blocks:** network BOM, power budget, physical install.

---

## D9. Backup strategy for critical footage

**Status:** Proposed *(README questions 4 and 7)*

**Recommendation:** three tiers, because they solve different problems.

1. **Configuration → this Git repository.** Free, versioned, and the fastest path to rebuilding after
   a total loss. Should be in place before any other backup work.
2. **Alert-clip archive → external USB drive, weekly `rsync`.** Only clips tied to alerts, not bulk
   recordings. Cheap and covers accidental deletion and array failure.
3. **Offsite for genuinely critical clips → Backblaze B2 or Wasabi**, $5–10/month, manually or
   automatically flagged clips only. Off-grid metered WAN makes bulk cloud sync impractical.

A backup that has never been restored is not a backup: the roadmap makes a restore rehearsal an exit
criterion rather than a task.

**Blocks:** Stage 5 and Stage 10 of the roadmap.

---

## D10. Home Assistant integration depth

**Status:** Proposed *(README question 5)*

**Recommendation:** **Home Assistant owns automation and notification; Frigate owns detection and
recording.** Resist implementing automation logic in both. Concretely, Home Assistant handles chain
camera activation, contact sensor correlation, notification routing, battery state-of-charge load
shedding, and the local-alert fallback path. Frigate handles detection, recording, retention, and
autotracking. MQTT is the only interface between them.

**Blocks:** automation design, container topology.

---

## D11. PTZ camera model selection

**Status:** Open *(README question 8)*

Cannot be answered generically. The hard requirement is ONVIF FOV RelativeMove
(`RelativePanTiltTranslationSpace` with a `TranslationSpaceFov` entry), and the ONVIF conformance
database is only a starting point because some cameras claim support and fail.

**Recommendation:** start from Dahua/EmpireTech — Frigate's autotracker was developed against a
Dahua SD1A404XB-GNR (sold as EmpireTech PTZ1A4M-4X-S2) and that family is the most consistently
reported as working. Exclude all current Reolink PTZs and Dahua "Lite" models. **Buy one unit and
verify with the community ONVIF capability script before ordering the rest.**

**Blocks:** autotracking work (Stage 7), camera BOM.

---

## D12. Motion tracking sensitivity thresholds

**Status:** Deferred *(README question 9)*

Not answerable from a desk. These are tuned per camera against real footage during the Stage 6 soak.
The roadmap treats tuning as a measured activity with a recorded before/after false-positive rate,
not a decision to be made in advance.

**Recommendation:** start at Frigate defaults, change one variable at a time, and record every
change in the repository so the tuning history survives.

---

## D13. Storage expansion budget

**Status:** Proposed *(README question 3)*

The README asks whether to budget $650–950 for storage expansion. Given that 10-day retention needs
1.8–4.2 TB and the recommended layout in D5 provides 4 TB usable, the honest answer is that the
current design is already over-provisioned.

**Recommendation:** **do not budget for storage expansion yet.** Spend the money on the power system
(D1), which is genuinely under-budgeted. Revisit only if measured GB/day during the Stage 6 soak
exceeds the estimates.
