# Off-Grid Home Security Hub

Self-hosted, AI-powered security camera hub built on a **ZimaBoard 2 1664** running
**Frigate NVR** with Google Coral TPU acceleration, **Home Assistant** automation, and
**Tailscale** remote access — no cloud subscription, no port forwarding.

Supports 12–20 ONVIF cameras with motion-triggered recording, PTZ auto-tracking,
and a 7–10 day rolling retention window.

## Hardware at a Glance

| Component  | Specification                                    |
| ---------- | ------------------------------------------------ |
| Server     | ZimaBoard 2 1664 (Intel N150, 16 GB LPDDR5)      |
| Recordings | 4 TB NVMe SSD (active) + 2× 4 TB SATA SSD (archive/redundancy) |
| AI         | 1–2× Google Coral USB TPU                        |
| Network    | Dual 2.5 GbE (camera VLAN + management)          |
| Cameras    | 12–20 ONVIF PTZ, PoE+, dual-stream               |

Full details: [docs/hardware.md](docs/hardware.md)

## Software Stack

| Component      | Role                                              |
| -------------- | ------------------------------------------------- |
| [Frigate](https://docs.frigate.video) | AI object detection, recording, PTZ auto-tracking |
| [Home Assistant](https://www.home-assistant.io) | Automation, notifications, device integration |
| [Mosquitto](https://mosquitto.org) | MQTT broker linking Frigate and Home Assistant |
| [Tailscale](https://tailscale.com) | Zero-config remote access (no exposed ports) |
| Docker Compose | Container orchestration                           |

## Repository Layout

```
├── docker-compose.yml        # Frigate + Mosquitto + Home Assistant stack
├── .env.example              # Environment template (copy to .env, never commit .env)
├── frigate/config/config.yml # Frigate configuration template
├── mosquitto/config/         # MQTT broker configuration
├── homeassistant/config/     # Home Assistant config (generated at first boot)
└── docs/                     # Architecture, deployment, and decision docs
```

## Quick Start

On the ZimaBoard (Ubuntu Server / Debian with Docker installed):

```bash
git clone https://github.com/Hoplite4Freedom/Off_grid_home_security_hub.git
cd Off_grid_home_security_hub
cp .env.example .env      # then edit .env with your camera IPs and passwords
docker compose up -d
```

Follow the full guide — including storage setup, MQTT users, and camera onboarding —
in **[docs/deployment.md](docs/deployment.md)**.

## Documentation

| Document | Contents |
| -------- | -------- |
| [docs/deployment.md](docs/deployment.md)       | Step-by-step install and first-boot guide |
| [docs/hardware.md](docs/hardware.md)           | Bill of materials, camera selection criteria, costs |
| [docs/network.md](docs/network.md)             | VLAN layout, PoE switching, QoS |
| [docs/storage.md](docs/storage.md)             | RAID/ZFS design, retention math, capacity planning |
| [docs/remote-access.md](docs/remote-access.md) | Tailscale setup and security model |
| [docs/decisions.md](docs/decisions.md)         | Decision log (decided + open questions) |

## Roadmap

- [x] Phase 0 — Architecture design and documentation
- [x] Phase 0.5 — Deployable software stack (this repo)
- [ ] Phase 1 — Deploy 12 cameras, validate storage and detection performance
- [ ] Phase 2 — Monitor for 2 weeks, tune detection zones and thresholds
- [ ] Phase 3 — Enable PTZ auto-tracking on high-priority cameras
- [ ] Phase 4 — Expand to 20 cameras if headroom allows
- [ ] Phase 5 — Advanced automation (chain activation, door/window sensors)
- [ ] Phase 6 — Offsite backup / cloud sync for critical footage

## License

[MIT](LICENSE)
