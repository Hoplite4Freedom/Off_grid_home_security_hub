# Remote Access — Tailscale

**Decision:** Tailscale (see [decisions.md](decisions.md)). WireGuard-based mesh VPN,
zero port forwarding, MFA through your identity provider, free for this deployment
size. The hub is never exposed to the public internet.

## Install on the ZimaBoard

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```

- Authenticate with the browser link that `tailscale up` prints.
- `--ssh` enables Tailscale SSH so you can administer the box remotely without
  opening port 22 to the LAN, with access controlled by tailnet ACLs.

## Tailnet Configuration (admin console)

1. **Enable MagicDNS** (DNS → MagicDNS) and set the machine name to `securityhub`,
   so services resolve as `securityhub` from any of your devices.
2. **Disable key expiry** for the ZimaBoard (Machines → ⋯ → Disable key expiry) so
   the hub doesn't drop off the tailnet after 180 days.
3. **Enforce MFA** on the identity provider you sign in with (Google/Microsoft/GitHub) —
   this satisfies the "2FA on all public-facing endpoints" requirement, because
   Tailscale login *is* the only entry point.

## Accessing Services

Install the Tailscale client on your phone/laptop, then:

| Service        | URL                              | Notes                          |
| -------------- | -------------------------------- | ------------------------------ |
| Frigate UI     | `https://securityhub:8971`       | Self-signed cert; authenticated |
| Home Assistant | `http://securityhub:8123`        |                                |
| MQTT           | `securityhub:1883`               | For debugging with MQTT Explorer |

### Optional: trusted HTTPS with `tailscale serve`

To get a valid Let's Encrypt certificate (no self-signed warning) for Frigate:

```bash
sudo tailscale serve --bg --https=443 https+insecure://localhost:8971
```

Frigate is then available at `https://securityhub.<tailnet-name>.ts.net`. Enable
HTTPS certificates first (admin console → DNS → HTTPS Certificates).

## Security Model

- **No inbound ports** are opened on the router; Tailscale establishes outbound
  connections only.
- The camera VLAN remains unreachable from the tailnet — remote users see Frigate
  and Home Assistant, never the cameras directly (see [network.md](network.md)).
- Use Tailscale ACLs to restrict which tailnet users/devices can reach
  `securityhub` if you share the tailnet with family members.
- Home Assistant mobile app: set the internal URL to `http://securityhub:8123`
  and it will work identically at home and away.
