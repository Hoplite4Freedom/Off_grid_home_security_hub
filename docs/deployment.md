# Deployment Guide

End-to-end guide to bring the hub from bare ZimaBoard to a running stack.

## 0. Prerequisites

- ZimaBoard 2 1664 with Ubuntu Server 24.04 LTS (or Debian 12) installed.
- Storage pool created and mounted — follow [storage.md](storage.md) first
  (default mount: `/mnt/frigate-media`).
- Cameras powered, on the camera VLAN, with static IPs/DHCP reservations
  ([network.md](network.md)), each with a dedicated viewer account.
- Google Coral USB TPU plugged into a **USB 3.1** port (blue).

### Install Docker Engine

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in for the group change to apply
docker --version && docker compose version
```

## 1. Clone and Configure

```bash
git clone https://github.com/Hoplite4Freedom/Off_grid_home_security_hub.git
cd Off_grid_home_security_hub
cp .env.example .env
nano .env    # set TZ, media path, MQTT password, camera credentials and IPs
```

Then edit `frigate/config/config.yml`:

- Adjust the two example cameras (`front_door`, `driveway_ptz`) to match your
  camera stream paths — the `stream1`/`stream2` RTSP suffixes vary by manufacturer
  (check with VLC or the ONVIF Device Manager).
- Set each camera's `detect.width`/`detect.height` to its **sub-stream** resolution.
- Copy the example blocks (go2rtc stream + camera entry + `.env` IP variable) for
  each additional camera.

## 2. Create MQTT Users

Mosquitto rejects anonymous connections, so create the accounts before first use:

```bash
touch mosquitto/config/passwd
docker compose up -d mosquitto
docker compose exec mosquitto mosquitto_passwd -b /mosquitto/config/passwd frigate '<FRIGATE_MQTT_PASSWORD from .env>'
docker compose exec mosquitto mosquitto_passwd -b /mosquitto/config/passwd homeassistant '<a second strong password>'
# Lock down the credentials file — the broker runs as uid 1883 inside the
# container and Mosquitto 2.1+ refuses world-readable password files.
sudo chown 1883:1883 mosquitto/config/passwd && sudo chmod 0600 mosquitto/config/passwd
docker compose restart mosquitto
```

Verify authentication is enforced (first command must be refused, second must succeed):

```bash
docker compose exec mosquitto mosquitto_pub -h localhost -t test -m hi                     # refused
docker compose exec mosquitto mosquitto_pub -h localhost -u frigate -P '<password>' -t test -m hi  # OK
```

## 3. Start the Stack

```bash
docker compose up -d
docker compose ps        # all three containers should be Up
docker compose logs -f frigate   # watch for camera connection errors
```

### First-login credentials

Frigate generates an admin password on first start:

```bash
docker logs frigate 2>&1 | grep -i password
```

Log in at `https://<zimaboard-ip>:8971` (self-signed certificate warning is
expected) and change the password under Settings → Users.

## 4. Verify Detection Hardware

In the Frigate UI, open **System metrics** and confirm:

- **Detector `coral1`** inference speed ≈ 8–10 ms (CPU fallback shows 50 ms+ —
  if so, check the Coral is on USB 3 and re-plug after first boot; the device
  re-enumerates once the delegate firmware loads).
- **GPU** decode active (VAAPI) — camera CPU usage should be low single digits
  per camera.

## 5. Home Assistant Onboarding

1. Browse to `http://<zimaboard-ip>:8123`, create the owner account.
2. Add the MQTT integration: Settings → Devices & Services → Add Integration →
   MQTT. Host: `<zimaboard-ip>`, port `1883`, user `homeassistant`, and the
   password from step 2.
3. Install the [Frigate integration](https://docs.frigate.video/integrations/home-assistant/)
   via HACS for cameras, sensors, and event entities. Frigate URL:
   `http://<zimaboard-ip>:5000` is not exposed by default — use
   `https://<zimaboard-ip>:8971` with a Frigate API user, or add a
   `127.0.0.1:5000:5000` port mapping if HA and Frigate share the host.
4. Enable the bundled automation package (chain camera activation, alert
   notifications, PTZ night mode — see
   `homeassistant/config/packages/security_hub.yaml`). Add this once to
   `homeassistant/config/configuration.yaml`, then restart Home Assistant:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

   The package assumes the example camera names (`front_door`, `driveway_ptz`)
   and PTZ presets named `home` and `entry` in the camera firmware — adjust to
   match your fleet. Arm/disarm push notifications with the
   `input_boolean.security_alerts_armed` toggle it creates.

## 6. Remote Access

Set up Tailscale per [remote-access.md](remote-access.md). Do **not** forward any
router ports.

## 7. Scaling Out (Phases 1–4)

Per the roadmap: start with 12 cameras, watch the [monitoring thresholds](storage.md#monitoring-thresholds)
for two weeks, tune zones/masks in the Frigate UI, then enable PTZ auto-tracking
(`onvif.autotracking.enabled: true` plus a `home` preset in the camera firmware)
on high-priority cameras, and expand toward 20 cameras while Coral utilization
stays under 70%.

## Updating

```bash
git pull
docker compose pull
docker compose up -d
```

Frigate config changes: edit `frigate/config/config.yml`, then
`docker compose restart frigate` (or use the UI's config editor, which validates
before saving).
