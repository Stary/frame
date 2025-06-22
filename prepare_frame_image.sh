#!/bin/bash

set -e

# Usage: prepare_frame_image.sh <DISK_DEVICE> <PARTITION_NUM> <MOUNT_POINT> <USER_HOME> <IMAGE_SIZE>
# Example: ./prepare_frame_image.sh /dev/sdc 1 /mnt/frame /home/orangepi 8G

# Default values
DISK_DEVICE="${1:-/dev/sdc}"
PARTITION_NUM="${2:-1}"
MOUNT_POINT="${3:-/mnt/frame}"
USER_HOME="${4:-/home/orangepi}"
IMAGE_SIZE="${5:-8G}"
case "$DISK_DEVICE" in
    /dev/mmcblk*|/dev/nvme*)
        PARTITION_DEVICE="${DISK_DEVICE}p${PARTITION_NUM}"
        ;;
    *)
        PARTITION_DEVICE="${DISK_DEVICE}${PARTITION_NUM}"
        ;;
esac
TS=$(date +%Y%m%d)

# Confirm settings with user
cat <<EOF
Preparing to create image with the following settings:
  Disk device:      $DISK_DEVICE
  Partition number: $PARTITION_NUM
  Partition device: $PARTITION_DEVICE
  Mount point:      $MOUNT_POINT
  User home:        $USER_HOME
  Image size:       $IMAGE_SIZE
  Output image:     frame.$TS.img.gz
EOF
read -p "Are you sure you want to proceed? This may overwrite or erase data. (yes/NO): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "This script requires root privileges, run it with sudo"
  exit 1
fi

# Check if partition is mounted elsewhere
if mount | grep -q "$PARTITION_DEVICE"; then
    echo "Error: $PARTITION_DEVICE is mounted elsewhere. Unmount it first."
    exit 1
fi

mkdir -p "$MOUNT_POINT"
umount "$MOUNT_POINT" 2>/dev/null || :

# Filesystem check and shrink to minimum
if ! e2fsck -f "$PARTITION_DEVICE"; then
    echo "e2fsck failed. Aborting." >&2
    exit 1
fi
if ! resize2fs -M "$PARTITION_DEVICE"; then
    echo "resize2fs -M failed. Aborting." >&2
    exit 1
fi

mount "$PARTITION_DEVICE" "$MOUNT_POINT"

# Remove user-specific, temporary and obsolete files
rm -fv "$MOUNT_POINT"/var/log/frame/*
rm -fv "$MOUNT_POINT"/var/log/resize*
rm -fv "$MOUNT_POINT"/home/orangepi/user.dat
rm -fv "$MOUNT_POINT"/etc/systemd/system/resizefs.service
rm -fv "$MOUNT_POINT"/usr/local/bin/resize_root.sh
rm -fv "$MOUNT_POINT"/root/.bash_history
rm -fv "$MOUNT_POINT"/home/orangepi/.bash_history
find "$MOUNT_POINT"/etc/netplan -maxdepth 1 -type f -name '*.yaml' ! -name 'orangepi-default.yaml' -exec rm -v {} +
# Broader cleanup
rm -rfv "$MOUNT_POINT"/tmp/* "$MOUNT_POINT"/var/tmp/*
rm -fv "$MOUNT_POINT"/var/mail/*
rm -rfv "$MOUNT_POINT"/root/.ssh "$MOUNT_POINT"/home/orangepi/.ssh
rm -fv "$MOUNT_POINT"/etc/ssh/*key*
rm -fv "$MOUNT_POINT"/etc/passwd- "$MOUNT_POINT"/etc/shadow- "$MOUNT_POINT"/etc/group- "$MOUNT_POINT"/etc/gshadow-
# Remove user history and cache
rm -rfv "$USER_HOME"/.cache/* "$USER_HOME"/.bash_history "$USER_HOME"/.viminfo

sync
umount "$MOUNT_POINT"

# Filesystem check and shrink to specified image size
if ! e2fsck -f "$PARTITION_DEVICE"; then
    echo "e2fsck failed after cleanup. Aborting." >&2
    exit 1
fi
if ! resize2fs "$PARTITION_DEVICE" "$IMAGE_SIZE"; then
    echo "resize2fs to $IMAGE_SIZE failed. Aborting." >&2
    exit 1
fi

parted "$DISK_DEVICE" resizepart "$PARTITION_NUM" "$IMAGE_SIZE"
parted "$DISK_DEVICE" print

resize2fs "$PARTITION_DEVICE"
e2fsck -f "$PARTITION_DEVICE"

# Calculate sectors to dump (end of partition + buffer)
END_SECTOR=$(parted "$DISK_DEVICE" unit s print | grep "^ *$PARTITION_NUM" | awk '{print $3}' | sed 's/s$//')
if [ -z "$END_SECTOR" ]; then
  echo "Error: Could not determine end sector of partition $PARTITION_NUM" >&2
  exit 1
fi
BUFFER_SECTORS=2048  # ~1MB buffer
SECTORS_COUNT=$((END_SECTOR + BUFFER_SECTORS))
echo "Dumping $SECTORS_COUNT sectors from $DISK_DEVICE..."

sync
# Create the compressed image
if ! dd if="$DISK_DEVICE" bs=512 count="$SECTORS_COUNT" status=progress | gzip > "frame.$TS.img.gz"; then
    echo "Error: dd or gzip failed." >&2
    exit 1
fi

echo "Image created: frame.$TS.img.gz"
