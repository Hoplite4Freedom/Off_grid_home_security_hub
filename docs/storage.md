# Storage Design

## RAID Options Considered

| RAID level | Usable space | Redundancy       | Notes                    |
| ---------- | ------------ | ---------------- | ------------------------ |
| RAID 1     | 4 TB         | 1 drive failure  | Maximum safety           |
| **RAID 5** | **8 TB**     | **1 drive failure** | **Selected — best balance** |
| RAID 10    | 4 TB         | 1 drive per pair | Performance + safety     |

**Selected: RAID 5** across the three 4 TB drives for 8 TB usable capacity.

## Recommended Implementation: ZFS RAIDZ1

ZFS RAIDZ1 provides the same single-drive redundancy as RAID 5 plus checksumming,
snapshots, and compression. Provisioning is scripted — run it with no arguments
first to list your disks, then pass the three stable disk IDs:

```bash
sudo ./scripts/storage-setup.sh
sudo ./scripts/storage-setup.sh \
  /dev/disk/by-id/nvme-XXXX \
  /dev/disk/by-id/ata-YYYY \
  /dev/disk/by-id/ata-ZZZZ
```

The script installs ZFS if needed, refuses disks with mounted filesystems,
requires typed confirmation before destroying anything, and creates:

- Pool `frigate-pool` (RAIDZ1, `ashift=12`, `atime=off`)
- Dataset `frigate-pool/media` mounted at `/mnt/frigate-media`
  (`compression=off` and `recordsize=1M` — video is already compressed and
  writes in large sequential segments)

Set `FRIGATE_MEDIA_PATH=/mnt/frigate-media` in `.env` to point the stack at the pool.

> **Alternative:** if you prefer a simple tiered layout instead of one pool, keep the
> NVMe as a standalone ext4 volume for active recordings and mirror the two SATA
> drives (mdadm RAID 1 or ZFS mirror) for archive. This trades capacity for simpler
> recovery.

## Retention Math

Recording is motion-triggered only (see `frigate/config/config.yml`): 7-day motion
retention, 10-day retention for alert/detection clips.

| Scenario         | Cameras | Daily usage (motion + tracking) | 10-day retention |
| ---------------- | ------- | ------------------------------- | ---------------- |
| Low-activity mix | 12      | ~120–180 GB                     | 1.2–1.8 TB       |
| Mixed activity   | 16      | ~180–300 GB                     | 1.8–3.0 TB       |
| High activity    | 20      | ~250–420 GB                     | 2.5–4.2 TB       |

Motion tracking adds ~20–30% overhead (continuous PTZ adjustment and higher frame
rates during active tracking). Worst case (4.2 TB) fits inside the 8 TB pool with
~50% headroom.

## Monitoring Thresholds

| Metric             | Warning       | Critical      | Action                    |
| ------------------ | ------------- | ------------- | ------------------------- |
| Disk usage         | 80%           | 90%           | Reduce retention days     |
| Daily write        | 200 GB        | 300 GB        | Review detection zones    |
| Detection rate     | 50/hr         | 100/hr        | Increase thresholds       |
| Coral utilization  | 70%           | 85%           | Add second TPU            |
| PTZ activity       | 50 events/hr  | 100 events/hr | Check for false triggers  |

Frigate's built-in System page (`Settings → System metrics`) reports storage,
detector inference speed, and per-camera FPS. ZFS pool health: `zpool status` and
`zfs list` (consider a cron alert on `zpool status -x`).

## Snapshots and Backup Hooks

- ZFS snapshots of the config datasets (not media) enable instant rollback:
  `zfs snapshot frigate-pool/media@pre-upgrade`.
- Offsite/cold backup of critical footage is Phase 6 — see the roadmap in the README
  and the pending decision in [decisions.md](decisions.md).
- This git repository itself is the configuration backup for the software stack.
