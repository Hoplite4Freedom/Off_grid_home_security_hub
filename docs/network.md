# Network Architecture

## Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                       ZimaBoard 2 1664                          │
│                                                                 │
│  Port 1 (2.5GbE) ──► Camera VLAN (12–20 cameras)                │
│  Port 2 (2.5GbE) ──► Management + Remote Access (Tailscale)     │
│                                                                 │
│  USB 3.1  ──► Google Coral TPU(s)                               │
│  PCIe x4  ──► NVMe SSD (active recordings)                      │
│  SATA ×2  ──► SSD array (archive / redundancy)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    Managed 2.5 GbE Switch
                    (VLAN-capable, PoE+)
```

## VLAN Segmentation

| VLAN        | Purpose                          | Internet access        |
| ----------- | -------------------------------- | ---------------------- |
| Camera      | All IP cameras                   | **Blocked** (no phone-home) |
| Management  | ZimaBoard, admin workstations    | Allowed                |
| IoT         | Zigbee hub, sensors, smart locks | Restricted             |

Rules of thumb:

- Cameras may only talk to the ZimaBoard's camera-VLAN interface (RTSP/ONVIF ports).
- Nothing on the camera VLAN can initiate connections to the internet or other VLANs.
- Management access from outside the LAN goes through Tailscale only — see
  [remote-access.md](remote-access.md). No port forwarding, ever.

## Switching and PoE

| Item             | Recommendation                        | Benefit                                    |
| ---------------- | ------------------------------------- | ------------------------------------------ |
| PoE+ switch      | 24-port 2.5 GbE PoE+ (16-port if ≤14 cameras) | Powers cameras, single cable per camera |
| VLAN tagging     | 802.1Q on camera/management/IoT       | Traffic isolation                          |
| QoS              | Prioritize RTSP traffic               | Prevents recording drops under load        |
| Link aggregation | Bond both 2.5 GbE ports (LACP)        | ~5 Gbps headroom for 20+ camera streams    |

## Bandwidth Budget

Per camera (dual stream): ~4–8 Mbps main (1080p–4MP H.264/H.265) + ~1 Mbps sub-stream.
Twenty cameras worst case ≈ 180 Mbps — comfortably inside a single 2.5 GbE link, but
PTZ tracking raises bitrate during events, so QoS on the camera VLAN is still recommended.
