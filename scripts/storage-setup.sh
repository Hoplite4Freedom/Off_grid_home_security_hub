#!/usr/bin/env bash
#
# storage-setup.sh — provision the ZFS RAIDZ1 recording pool for the security hub.
#
# Creates a RAIDZ1 pool (single-drive redundancy, RAID 5 equivalent) from three or
# more disks and a media dataset tuned for video recordings, mounted where the
# Docker stack expects it (FRIGATE_MEDIA_PATH in .env).
#
# Usage:
#   sudo ./scripts/storage-setup.sh                      # list candidate disks
#   sudo ./scripts/storage-setup.sh <disk-id> <disk-id> <disk-id> [...]
#
# Disks must be given as stable /dev/disk/by-id/ paths (never /dev/sdX — those
# can change between boots). Example:
#   sudo ./scripts/storage-setup.sh \
#     /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_4TB_XXXX \
#     /dev/disk/by-id/ata-CT4000MX500SSD1_YYYY \
#     /dev/disk/by-id/ata-CT4000MX500SSD1_ZZZZ
#
# WARNING: this DESTROYS all data on the disks you pass in.

set -euo pipefail

POOL_NAME="${POOL_NAME:-frigate-pool}"
DATASET_NAME="${DATASET_NAME:-media}"
MOUNTPOINT="${MOUNTPOINT:-/mnt/frigate-media}"

err() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "must run as root (use sudo)"

if [[ $# -eq 0 ]]; then
    echo "No disks specified. Candidate disks on this system:"
    echo
    lsblk -dno NAME,SIZE,MODEL,SERIAL | sed 's/^/  /'
    echo
    echo "Stable identifiers (use these as arguments):"
    echo
    find /dev/disk/by-id -maxdepth 1 \( -name 'ata-*' -o -name 'nvme-*' -o -name 'scsi-*' \) ! -name '*-part*' 2>/dev/null | sort | sed 's/^/  /'
    echo
    echo "Re-run with three or more disk paths to create the ${POOL_NAME} RAIDZ1 pool."
    exit 0
fi

[[ $# -ge 3 ]] || err "RAIDZ1 needs at least 3 disks (got $#). For a 2-disk mirror, create it manually: zpool create ${POOL_NAME} mirror <disk> <disk>"

for disk in "$@"; do
    [[ "$disk" == /dev/disk/by-id/* ]] || err "$disk is not a /dev/disk/by-id/ path"
    [[ -b "$disk" ]] || err "$disk is not a block device"
    dev="$(readlink -f "$disk")"
    if lsblk -no MOUNTPOINT "$dev" | grep -q .; then
        err "$disk ($dev) has mounted filesystems — refusing to touch it"
    fi
done

if ! command -v zpool >/dev/null 2>&1; then
    echo "Installing ZFS utilities..."
    apt-get update -qq && apt-get install -y -qq zfsutils-linux
fi

zpool list "$POOL_NAME" >/dev/null 2>&1 && err "pool '$POOL_NAME' already exists"

echo
echo "About to create ZFS pool '$POOL_NAME' (RAIDZ1) from:"
printf '  %s\n' "$@"
echo
echo "Dataset:    $POOL_NAME/$DATASET_NAME"
echo "Mountpoint: $MOUNTPOINT"
echo
echo ">>> ALL DATA ON THESE DISKS WILL BE DESTROYED <<<"
echo
read -r -p "Type the pool name ($POOL_NAME) to continue: " confirm
[[ "$confirm" == "$POOL_NAME" ]] || err "confirmation did not match — aborting"

# ashift=12: align to 4K sectors (correct for all modern SSDs)
# atime=off: recordings are write-heavy; access-time updates are wasted IO
zpool create -o ashift=12 -O atime=off "$POOL_NAME" raidz1 "$@"

# compression=off: H.264/H.265 video is already compressed; skip the CPU cost
# recordsize=1M: large sequential video segments benefit from large records
zfs create \
    -o compression=off \
    -o recordsize=1M \
    -o mountpoint="$MOUNTPOINT" \
    "$POOL_NAME/$DATASET_NAME"

echo
zpool status "$POOL_NAME"
echo
echo "Done. Recordings pool mounted at $MOUNTPOINT"
echo "Next steps:"
echo "  1. Ensure FRIGATE_MEDIA_PATH=$MOUNTPOINT in .env"
echo "  2. Check pool health any time with: zpool status -x"
