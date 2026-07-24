# Off_grid_home_security_hub
Home camera and security hub - Zima board2 1664, Dual Coral AI, 3x 4TB storage and Backup

## Project status

This document is the original design session summary. It has since been reviewed, and the review
findings, open decisions, and delivery plan are tracked separately:

- [Repository review](docs/repository-review.md) — findings against this design, by severity
- [Decision register](docs/decisions.md) — the open questions below, with recommended defaults
- [Path to completion](docs/path-to-completion.md) — staged plan with measurable exit criteria

Several figures and the Frigate configuration snippet in this document need correction before use;
see the review for details.


Home Lab Security Camera Hub - Session Summary
Date: March 15, 2026
Session Type: Technical Planning & Architecture Design
Topic: ZimaBoard 2 1664 + Frigate Security Camera Deployment
Version: 3.0 (Updated with Motion Tracking Capabilities)

Executive Summary
Designed a scalable home lab security camera system using a ZimaBoard 2 1664 single-board server running Frigate for AI-powered surveillance. The system supports 12–20 cameras with motion tracking capability, motion-triggered recording, 7–10 day rolling retention, remote access, and advanced automation capabilities including chain camera activation.

Hardware Specifications
ZimaBoard 2 1664
Component	Specification
CPU	Intel N150 quad-core processor
RAM	16GB LPDDR5 (4800 MHz)
Storage Interfaces	PCIe x4 (NVMe), 2× SATA III (6Gb/s)
Network	Dual 2.5GbE Ethernet ports
USB	2× USB 3.1 Type-A ports
Form Factor	Aluminum chassis
Storage Architecture
Component	Capacity	Purpose
NVMe SSD	4 TB	Active recordings (fast access)
SATA SSD #1	4 TB	Archive/redundancy
SATA SSD #2	4 TB	Archive/redundancy
Total Usable	4–8 TB (RAID dependent)	7–10 day rolling retention
AI Acceleration
Component	Quantity	Purpose
Google Coral TPU	1–2 units	Object detection offloading
Camera Infrastructure
Scale
Total Cameras: 12–20
Activity Profile: 4–6 high-activity, remaining low-activity
Streams per Camera: 2 (main + sub-feed for detection)
PTZ Control: ONVIF protocol support
Motion Tracking: Auto-tracking enabled on all cameras
Recording Strategy
Parameter	Setting
Recording Mode	Motion-triggered only
Detection FPS	5 FPS (sub-stream)
Tracking FPS	10–15 FPS (during active tracking)
Retention	7–10 days rolling
Object Tracking	Person, car (min_score: 0.6–0.7)
Night Vision	All cameras (IR mitigation configured)
Motion Tracking Specifications
Feature	Configuration
Tracking Mode	Auto-track on detected objects
Smooth Movement	Enabled (prevent jerky PTZ)
Track Timeout	30 seconds after motion stops
Priority Objects	Person > Car > Other
Zone Locking	Restrict tracking to defined areas
Storage Estimates (Including Tracking Overhead)
Scenario	Cameras	Daily Usage (Motion + Tracking)	10-Day Retention
Low Activity Mix	12	~120–180 GB	1.2–1.8 TB
Mixed Activity	16	~180–300 GB	1.8–3.0 TB
High Activity	20	~250–420 GB	2.5–4.2 TB
Note: Motion tracking adds ~20–30% overhead due to continuous PTZ adjustments and higher frame rate during active tracking.

Network Architecture
┌─────────────────────────────────────────────────────────────────┐
│                    ZimaBoard 2 1664                             │
│                                                                 │
│  Port 1 (2.5GbE) ──► Camera VLAN (12–20 cameras)               │
│  Port 2 (2.5GbE) ──► Management + Remote Access                │
│                                                                 │
│  USB 3.1 ──► Google Coral TPU                                   │
│  PCIe x4 ──► NVMe SSD (active recordings)                      │
│  SATA x2 ──► SSD Array (archive/redundancy)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    Managed 2.5GbE Switch
                    (VLAN-capable, PoE+)
Security Considerations
VLAN Segmentation: Cameras isolated from management network
Remote Access: Tailscale or Cloudflare Tunnel (no port forwarding)
Encryption: HTTPS with valid certificates (Let's Encrypt)
Authentication: 2FA on all public-facing endpoints
Software Stack
Component	Purpose
Frigate	AI detection, recording, event management, motion tracking
Home Assistant	Complex automation, device integration, PTZ coordination
MQTT Broker	Communication between Frigate and Home Assistant
Docker	Containerized deployment
Linux	Base OS (Ubuntu Server/Debian/Alpine)
Advanced Automation Features
Chain Camera Activation: Front doorbell motion → Indoor entry camera activation
Motion Tracking Coordination: Multiple cameras track same subject across zones
Door/Window Detection: Physical sensors or camera-based AI
Event Logging: Centralized database for audit trails
Push Notifications: Real-time alerts for detected events with tracking status
Frigate Configuration Highlights (With Motion Tracking)
# Key optimization settings
detect:
  fps: 5  # Reduced from 30 for efficiency

motion:
  threshold: 50  # Higher = fewer false triggers
  contour_area: 40  # Ignore small movements
  
objects:
  track:
    - person
    - car
  filters:
    person:
      min_score: 0.7
    car:
      min_score: 0.6

# Motion Tracking Configuration
ptz:
  auto:
    mode: on_event
    position: home
    timeout: 30  # Return to home after 30 seconds
    smooth: true  # Prevent jerky movements

record:
  retain:
    default: 7
  events:
    retain:
      default: 10
      mode: active_objects
Motion Tracking Considerations
Bandwidth: Tracking increases stream bitrate during active events
Storage: Continuous PTZ movement creates more event segments
Camera Wear: Mechanical PTZ components have limited lifespan
False Triggers: Wind, shadows can cause unwanted tracking movements
Night Vision Mitigation
Exclude sky/ground areas via motion masks
Higher threshold at night (55+)
Clean IR housings regularly
Adjust camera angles to minimize IR bounce
Storage Configuration Options
RAID Level	Usable Space	Redundancy	Recommendation
RAID 1	4 TB	1 drive failure	Maximum safety
RAID 5	8 TB	1 drive failure	Best balance
RAID 10	4 TB	1 drive/pair	Performance + safety
Selected: RAID 5 for 8 TB usable capacity (balance of capacity and redundancy)

Monitoring & Maintenance
Metric	Warning	Critical	Action
Disk Usage	80%	90%	Delete oldest clips
Daily Write	200 GB	300 GB	Review detection zones
Detection Rate	50/hr	100/hr	Increase thresholds
Coral Utilization	70%	85%	Add second TPU
PTZ Activity	50 events/hr	100 events/hr	Check for false triggers
Phased Rollout Plan
Phase 1: Deploy 12 cameras, validate storage and detection performance
Phase 2: Monitor for 2 weeks, adjust detection zones and thresholds
Phase 3: Enable motion tracking on high-priority cameras first
Phase 4: Expand to 20 cameras if headroom allows
Phase 5: Implement advanced automation (chain activation, door/window sensors)
Phase 6: Add external backup or cloud sync for critical footage
Cost Summary
Component	Estimated Cost
ZimaBoard 2 1664	$279–409
4 TB NVMe SSD	$250–350
4 TB SATA SSD (×2)	$400–600
Google Coral TPU	$60–80
Managed Switch (2.5GbE)	$100–200
PTZ Cameras (12–20)	$1,200–3,000
Total	~$2,289–4,639
Additional Recommendations for Efficiency & Cost-Effectiveness
1. Power Optimization
Component	Recommendation	Estimated Savings
UPS Battery	APC or CyberPower 600–1000VA	Prevents data corruption during outages
Power Monitoring	Smart plug with energy tracking	Identify power spikes, optimize schedules
Sleep Modes	Configure HDD spin-down for inactive periods	10–20% reduction in idle power
Efficient PSU	80+ Gold rated power supply	5–10% efficiency gain
2. Storage Cost Optimization
Strategy	Implementation	Cost Impact
Tiered Storage	NVMe for 7 days, HDD for 30+ days archive	30–40% reduction in SSD costs
HDD for Cold Archive	Replace one SATA SSD with 8–16 TB HDD	$150–200 savings vs. SSD
Compressed Recording	Enable H.265 encoding where supported	40–50% storage reduction
Deduplication	ZFS or btrfs for snapshot dedup	10–20% additional space savings
3. Network Efficiency
Component	Recommendation	Benefit
PoE+ Switch	24-port 2.5GbE PoE+ switch	Powers cameras, reduces cable clutter
VLAN Tagging	Separate camera, management, IoT VLANs	Improved security and traffic isolation
QoS Rules	Prioritize camera traffic on congested networks	Prevents recording drops during peak usage
Link Aggregation	Bond both 2.5GbE ports for 5 GbE throughput	Headroom for 20+ camera streams
4. AI & Detection Optimization
Strategy	Implementation	Efficiency Gain
Region of Interest	Define detection zones per camera	30–50% reduction in false positives
Time-Based Sensitivity	Lower sensitivity during low-risk hours	20–30% reduction in storage
Multi-Coral Load Balancing	Distribute cameras across 2 Coral TPUs	40–60% increase in detection capacity
Pre-trained Models	Use Frigate's optimized COCO models	Faster inference, lower CPU usage
5. Motion Tracking Optimization
Strategy	Implementation	Efficiency Gain
Tracking Zones	Limit PTZ movement to defined areas	20–30% reduction in mechanical wear
Object Priority	Track persons first, cars second	Focus resources on high-value targets
Cooldown Period	60-second cooldown between tracks	Prevents rapid PTZ cycling
Night Mode	Disable tracking during low-light hours	Reduces false triggers from IR noise
6. Automation Enhancements
Feature	Tool	Cost
Door/Window Sensors	Zigbee (Aqara, Sonoff)	$15–30 per sensor
Smart Locks	Integration with Home Assistant	$100–200 per lock
Voice Control	Home Assistant + Alexa/Google	$0–50 (existing devices)
Geofencing	Mobile app location triggers	$0 (built-in)
7. Backup & Disaster Recovery
Strategy	Implementation	Cost
Offsite Sync	rsync to external USB drive weekly	$0–100 (drive cost)
Cloud Backup	Backblaze B2 or Wasabi for critical clips	$5–10/month
Snapshot Rotation	ZFS snapshots with automated cleanup	$0 (software)
Configuration Backup	Git repository for Frigate/HA configs	$0 (GitHub free tier)
8. Cooling & Reliability
Component	Recommendation	Benefit
Case Fans	120mm PWM fans with temperature control	Prevents thermal throttling
Ambient Monitoring	Temperature/humidity sensors	Early warning for environmental issues
Cable Management	Velcro ties, labeled cables	Easier troubleshooting
Documentation	Network diagram, IP inventory	Faster incident response
9. PTZ Camera Selection Criteria
Feature	Recommendation	Why It Matters
ONVIF Profile S	Required	Ensures Frigate compatibility
Speed Dome	360° pan, 90° tilt	Full coverage area
IP66/67 Rating	Weatherproof	Outdoor durability
WDR (Wide Dynamic Range)	120dB+	Handles backlight/shadows
Night Vision Range	30m+ IR	Effective low-light tracking
PoE+ Support	802.3at	Simplified power delivery
10. Phased Budget Optimization
Phase	Investment	Priority
Phase 1	ZimaBoard + 1× Coral + 4 TB NVMe	Core functionality
Phase 2	Add 2× SATA SSDs for redundancy	Data safety
Phase 3	PoE+ switch + PTZ cameras	Network efficiency + tracking
Phase 4	Zigbee sensors + Home Assistant	Automation depth
Phase 5	Offsite backup + monitoring	Disaster recovery
Total Estimated Budget (Full Build): $2,300–4,650
Minimum Viable Build: $1,200–1,800 (12 cameras, 7-day retention, no tracking)

Outstanding Questions & Decisions Needed
Question	Status
Physical door/window sensors vs. camera-based AI?	Pending
Remote access method (Tailscale vs. Cloudflare Tunnel)?	Pending
Budget for storage expansion (current: ~$650–950)?	Pending
Backup strategy for critical footage?	Pending
Home Assistant integration depth?	Pending
PoE switch capacity (24-port vs. 16-port)?	Pending
Offsite backup provider selection?	Pending
PTZ camera brand/model selection?	Pending
Motion tracking sensitivity thresholds?	Pending
Next Session Agenda
Finalize Frigate config.yml with motion tracking optimizations
Configure RAID setup (mdadm or ZFS)
Set up remote access (Tailscale/Cloudflare Tunnel)
Draft Home Assistant automation rules for chain activation + tracking
Establish monitoring dashboard (Prometheus/Grafana)
Review power optimization and cooling requirements
Select backup strategy and implement offsite sync
Select PTZ camera models with ONVIF compatibility
Configure tracking zones and cooldown periods
References & Resources
Resource	URL
Frigate Documentation	https://docs.frigate.video
ZimaBoard Shop	https://shop.zimaspace.com
Home Assistant	https://home-assistant.io
Tailscale	https://tailscale.com
Cloudflare Tunnel	https://developers.cloudflare.com/cloudflare-one/connections/connect-apps
Google Coral	https://coral.ai
ZFS on Linux	https://openzfs.github.io
ONVIF Device Manager	https://onvif.org
End of Session Summary
This document can be loaded into the next session to resume discussion.

Would you like me to create a separate configuration template file for the Frigate YAML with motion tracking settings, or shall we discuss specific PTZ camera models that would work best with your ONVIF requirements?
