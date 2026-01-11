#!/bin/bash

set -e

# Usage: prepare_frame_image.sh <DISK_DEVICE> <PARTITION_NUM> <IMAGE_SIZE> <MOUNT_POINT> <USER_HOME>
# Example: ./prepare_frame_image.sh /dev/sdc 1 /mnt/frame /home/orangepi 8G

# Default values
DISK_DEVICE="${1:-/dev/sdc}"
PARTITION_NUM="${2:-1}"
IMAGE_SIZE="${3:-8G}"
if [[ -n "$IMAGE_SIZE" && ! "$IMAGE_SIZE" =~ ^[0-9] ]]; then
  IMAGE_SIZE=""
fi
MOUNT_POINT="${4:-/mnt/frame}"
USER_HOME="${5:-/home/orangepi}"
case "$DISK_DEVICE" in
    /dev/mmcblk*|/dev/nvme*)
        PARTITION_DEVICE="${DISK_DEVICE}p${PARTITION_NUM}"
        ;;
    *)
        PARTITION_DEVICE="${DISK_DEVICE}${PARTITION_NUM}"
        ;;
esac
TS=$(date +%Y%m%d)
OUTPUT_IMAGE="frame.$TS.img.gz"

size_to_bytes() {
  local size="$1"
  case "$size" in
    *iB|*i)
      numfmt --from=iec --to=none "$size"
      ;;
    *[KMGTP]B|*[KMGTP])
      numfmt --from=si --to=none "$size"
      ;;
    *)
      numfmt --from=none --to=none "$size"
      ;;
  esac
}

partition_start_sector() {
  parted -m "$DISK_DEVICE" unit s print | awk -F: -v part="$PARTITION_NUM" '$1 == part {gsub(/s$/, "", $2); print $2}'
}

partition_end_sector() {
  parted -m "$DISK_DEVICE" unit s print | awk -F: -v part="$PARTITION_NUM" '$1 == part {gsub(/s$/, "", $3); print $3}'
}

check_commands() {
  local missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: Required command '$cmd' not found." >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

# Confirm settings with user
cat <<EOF
Preparing to create image with the following settings:
  Disk device:      $DISK_DEVICE
  Partition number: $PARTITION_NUM
  Partition device: $PARTITION_DEVICE
  Mount point:      $MOUNT_POINT
  User home:        $USER_HOME
  Image size:       ${IMAGE_SIZE:-"(skipped)"}
  Output image:     $OUTPUT_IMAGE
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

# Check for required commands before starting long-running operations
REQUIRED_CMDS=(
  awk sed grep find mount umount e2fsck resize2fs numfmt
  parted blockdev partprobe dd gzip sync rm mv
)
check_commands "${REQUIRED_CMDS[@]}"

# Check if partition is mounted elsewhere
if mount | grep -q "$PARTITION_DEVICE"; then
    echo "Error: $PARTITION_DEVICE is mounted elsewhere. Unmount it first."
    exit 1
fi

mkdir -p "$MOUNT_POINT"
umount "$MOUNT_POINT" 2>/dev/null || :

if [ -n "$IMAGE_SIZE" ]; then
  TARGET_BYTES=$(size_to_bytes "$IMAGE_SIZE")
  if [ -z "$TARGET_BYTES" ] || [ "$TARGET_BYTES" -le 0 ]; then
      echo "Invalid IMAGE_SIZE: $IMAGE_SIZE" >&2
      exit 1
  fi

  SECTOR_SIZE=$(blockdev --getss "$DISK_DEVICE")
  if [ -z "$SECTOR_SIZE" ] || [ "$SECTOR_SIZE" -le 0 ]; then
      echo "Error: Could not determine sector size for $DISK_DEVICE" >&2
      exit 1
  fi

  START_SECTOR=$(partition_start_sector)
  if [ -z "$START_SECTOR" ]; then
      echo "Error: Could not determine start sector of partition $PARTITION_NUM" >&2
      exit 1
  fi

  TARGET_SECTORS=$((TARGET_BYTES / SECTOR_SIZE))
  END_SECTOR=$((TARGET_SECTORS - 1))
  if [ "$END_SECTOR" -le "$START_SECTOR" ]; then
      echo "Error: IMAGE_SIZE too small for partition $PARTITION_NUM" >&2
      exit 1
  fi

  CURRENT_END_SECTOR=$(partition_end_sector)
  if [ -z "$CURRENT_END_SECTOR" ]; then
      echo "Error: Could not determine current end sector of partition $PARTITION_NUM" >&2
      exit 1
  fi

  if [ "$END_SECTOR" -lt "$CURRENT_END_SECTOR" ]; then
      check_commands sfdisk
  fi

  # Filesystem check and shrink to minimum
  if ! e2fsck -f "$PARTITION_DEVICE"; then
      echo "e2fsck failed. Aborting." >&2
      exit 1
  fi
  if ! resize2fs -M "$PARTITION_DEVICE"; then
      echo "resize2fs -M failed. Aborting." >&2
      exit 1
  fi
fi

mount "$PARTITION_DEVICE" "$MOUNT_POINT"

# No need to update frame.cfg as user.dat is being removed that makes watchdog to run update
#if [ -s "$MOUNT_POINT"/home/orangepi/frame.cfg ]; then
#  sed -i "s/UPDATE=no/UPDATE=yes/" "$MOUNT_POINT"/home/orangepi/frame.cfg
#  echo "Update flag set in $MOUNT_POINT/home/orangepi/frame.cfg"
#else
#  echo "Error: $MOUNT_POINT/home/orangepi/frame.cfg not found. Aborting." >&2
#  exit 1
#fi

grep -v -i -E -e "(wifi|password)" "$MOUNT_POINT"/home/orangepi/frame.cfg > "$MOUNT_POINT"/home/orangepi/frame.cfg.new
mv "$MOUNT_POINT"/home/orangepi/frame.cfg.new "$MOUNT_POINT"/home/orangepi/frame.cfg
# Remove user-specific, temporary and obsolete files
rm -fv "$MOUNT_POINT"/var/log/frame/*
rm -fv "$MOUNT_POINT"/var/log/resize*
rm -fv "$MOUNT_POINT"/home/orangepi/user.dat
rm -fv "$MOUNT_POINT"/home/orangepi/update.flag
rm -fv "$MOUNT_POINT"/etc/systemd/system/resizefs.service
rm -fv "$MOUNT_POINT"/usr/local/bin/resize_root.sh
rm -fv "$MOUNT_POINT"/root/.bash_history
rm -fv "$MOUNT_POINT"/home/orangepi/.bash_history
rm -fv "$MOUNT_POINT"/media/photo/frame.cfg
rm -rfv "$MOUNT_POINT"/media/photo
find "$MOUNT_POINT"/etc/netplan -maxdepth 1 -type f -name '*.yaml' ! -name 'orangepi-default.yaml' -exec rm -v {} +
# Broader cleanup
rm -rfv "$MOUNT_POINT"/tmp/* "$MOUNT_POINT"/var/tmp/*
rm -fv "$MOUNT_POINT"/var/mail/*
rm -rfv "$MOUNT_POINT"/root/.ssh "$MOUNT_POINT"/home/orangepi/.ssh
rm -fv "$MOUNT_POINT"/etc/passwd- "$MOUNT_POINT"/etc/shadow- "$MOUNT_POINT"/etc/group- "$MOUNT_POINT"/etc/gshadow-
# Remove user history and cache
rm -rfv "$USER_HOME"/.cache/* "$USER_HOME"/.bash_history "$USER_HOME"/.viminfo

sync

sudo sed -i '/[[:space:]]\/[[:space:]]/ s/commit=[0-9]\+/commit=1/' "$MOUNT_POINT"/etc/fstab

umount "$MOUNT_POINT"

if [ -n "$IMAGE_SIZE" ]; then
    # Filesystem check and resize to requested image size
    if ! e2fsck -f "$PARTITION_DEVICE"; then
        echo "e2fsck failed after cleanup. Aborting." >&2
        exit 1
    fi

    if [ "$END_SECTOR" -lt "$CURRENT_END_SECTOR" ]; then
        NEW_SIZE_SECTORS=$((END_SECTOR - START_SECTOR + 1))
        if [ "$NEW_SIZE_SECTORS" -le 0 ]; then
            echo "Error: Computed partition size is invalid for shrinking." >&2
            exit 1
        fi
        echo ",${NEW_SIZE_SECTORS}" | sfdisk --no-reread -N "$PARTITION_NUM" "$DISK_DEVICE"
    else
        parted -s "$DISK_DEVICE" unit s resizepart "$PARTITION_NUM" "${END_SECTOR}s"
    fi
    parted "$DISK_DEVICE" print

    partprobe "$DISK_DEVICE" 2>/dev/null || blockdev --rereadpt "$DISK_DEVICE"
    resize2fs "$PARTITION_DEVICE"
    e2fsck -f "$PARTITION_DEVICE"
else
    echo "IMAGE_SIZE is not set. Skipping partition resize and filesystem growth."
fi

# Calculate sectors to dump (end of partition + buffer)
END_SECTOR=$(partition_end_sector)
if [ -z "$END_SECTOR" ]; then
  echo "Error: Could not determine end sector of partition $PARTITION_NUM" >&2
  exit 1
fi
BUFFER_SECTORS=2048  # ~1MB buffer
SECTORS_COUNT=$((END_SECTOR + BUFFER_SECTORS))
echo "Dumping $SECTORS_COUNT sectors from $DISK_DEVICE..."

sync
# Detect dd status=progress support for this environment
DD_STATUS_ARG=""
if dd --help 2>/dev/null | grep -q -E 'progress'; then
  DD_STATUS_ARG="status=progress"
else
  echo "Note: dd does not support status=progress; continuing without progress output."
fi
# Create the compressed image
if ! dd if="$DISK_DEVICE" bs=512 count="$SECTORS_COUNT" $DD_STATUS_ARG | gzip > "$OUTPUT_IMAGE"; then
    echo "Error: dd or gzip failed." >&2
    exit 1
fi

echo "Image created: $OUTPUT_IMAGE"
echo "To write to another MicroSD:"
if [ -n "$DD_STATUS_ARG" ]; then
  echo "  gzip -dc \"$OUTPUT_IMAGE\" | sudo dd of=/dev/sdX bs=4M conv=fsync $DD_STATUS_ARG"
else
  echo "  gzip -dc \"$OUTPUT_IMAGE\" | sudo dd of=/dev/sdX bs=4M conv=fsync"
fi
echo "  # replace /dev/sdX with the target disk (not a partition)"
