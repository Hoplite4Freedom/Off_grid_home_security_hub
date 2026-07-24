# Hardware

## ZimaBoard 2 1664

| Component          | Specification                        |
| ------------------ | ------------------------------------ |
| CPU                | Intel N150 quad-core                 |
| RAM                | 16 GB LPDDR5 (4800 MHz)              |
| Storage interfaces | PCIe x4 (NVMe), 2× SATA III (6 Gb/s) |
| Network            | Dual 2.5 GbE Ethernet                |
| USB                | 2× USB 3.1 Type-A                    |
| Form factor        | Passively cooled aluminum chassis    |

## Storage

| Component   | Capacity | Purpose                          |
| ----------- | -------- | -------------------------------- |
| NVMe SSD    | 4 TB     | Active recordings (fast access)  |
| SATA SSD #1 | 4 TB     | Archive / redundancy             |
| SATA SSD #2 | 4 TB     | Archive / redundancy             |

Usable capacity is 4–8 TB depending on RAID level — see [storage.md](storage.md)
for the selected layout and retention math.

## AI Acceleration

| Component        | Quantity | Purpose                                |
| ---------------- | -------- | -------------------------------------- |
| Google Coral TPU | 1–2 USB  | Object detection offload from the CPU  |

One Coral comfortably handles 12 cameras at 5 FPS detection. Add the second TPU
when sustained Coral utilization exceeds ~70% (see monitoring thresholds in
[storage.md](storage.md)).

## Camera Fleet

| Parameter           | Value                                        |
| ------------------- | -------------------------------------------- |
| Total cameras       | 12–20                                        |
| Activity profile    | 4–6 high-activity, remainder low-activity    |
| Streams per camera  | 2 (main for recording, sub for detection)    |
| PTZ control         | ONVIF protocol                               |
| Motion tracking     | Auto-tracking on PTZ-capable cameras         |
| Night vision        | All cameras (IR mitigation configured)       |

### PTZ Camera Selection Criteria

| Feature             | Requirement       | Why it matters                        |
| ------------------- | ----------------- | ------------------------------------- |
| ONVIF Profile S     | Required          | Frigate PTZ/auto-tracking compatibility |
| Speed dome          | 360° pan, 90° tilt | Full coverage area                   |
| Weatherproofing     | IP66/IP67         | Outdoor durability                    |
| WDR                 | 120 dB+           | Handles backlight and shadows         |
| Night vision        | 30 m+ IR          | Effective low-light tracking          |
| Power               | PoE+ (802.3at)    | Single-cable power and data           |

## Power and Cooling

| Item              | Recommendation                              | Benefit                                  |
| ----------------- | ------------------------------------------- | ---------------------------------------- |
| UPS               | APC or CyberPower 600–1000 VA               | Prevents data corruption during outages  |
| Power monitoring  | Smart plug with energy tracking             | Identify spikes, optimize schedules      |
| PSU               | 80+ Gold rated                              | 5–10% efficiency gain                    |
| Case fans         | 120 mm PWM, temperature-controlled          | Prevents thermal throttling              |
| Ambient sensors   | Temperature/humidity monitoring             | Early warning for environmental issues   |

## Cost Summary

| Component               | Estimated Cost  |
| ----------------------- | --------------- |
| ZimaBoard 2 1664        | $279–409        |
| 4 TB NVMe SSD           | $250–350        |
| 4 TB SATA SSD (×2)      | $400–600        |
| Google Coral TPU        | $60–80          |
| Managed 2.5 GbE switch  | $100–200        |
| PTZ cameras (12–20)     | $1,200–3,000    |
| **Total (full build)**  | **~$2,300–4,650** |

Minimum viable build (12 cameras, 7-day retention, no tracking): **$1,200–1,800**.

### Cost Optimization Options

- **Tiered storage** — NVMe for the first 7 days, HDD for 30+ day archive (30–40% SSD cost reduction).
- **HDD cold archive** — replace one SATA SSD with an 8–16 TB HDD ($150–200 savings).
- **H.265 recording** — enable on cameras that support it (40–50% storage reduction).
