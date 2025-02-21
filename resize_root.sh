#!/bin/bash
set -e

LOG_FILE="/var/log/resizefs.log"

echo "========== Resize Root Partition Script ==========" | tee "$LOG_FILE"
date | tee -a "$LOG_FILE"

# Check if necessary tools are installed
for cmd in parted resize2fs lsblk findmnt systemctl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Command '$cmd' not found. Please install it." | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Get partition device
PARTITION_DEVICE=$(findmnt -n -o SOURCE / | sed -r 's/( )+//g')
if [ -z "$PARTITION_DEVICE" ]; then
    echo "ERROR: Could not determine root partition device!" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Partition device: $PARTITION_DEVICE" | tee -a "$LOG_FILE"

# Get disk device
DISK_DEVICE="/dev/$(lsblk -no pkname "$PARTITION_DEVICE" | sed -r 's/( )+//g')"
if [ -z "$DISK_DEVICE" ]; then
    echo "ERROR: Could not determine main disk device!" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Disk device: $DISK_DEVICE" | tee -a "$LOG_FILE"

# Get partition number
PARTITION_N=$(lsblk -no PARTN "$PARTITION_DEVICE" | sed -r 's/( )+//g')
if [ -z "$PARTITION_N" ]; then
    echo "ERROR: Could not determine partition number!" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Partition N: $PARTITION_N" | tee -a "$LOG_FILE"

# Get available disk size
TOTAL_DISK_SIZE=$(lsblk -bno SIZE "$DISK_DEVICE" | sort -r | head -1 | sed -r 's/( )+//g')
PARTITION_END=$(parted "$DISK_DEVICE" -ms unit B print | grep "^$PARTITION_N" | cut -d: -f3 | sed 's/B//g')

if [ -z "$TOTAL_DISK_SIZE" ] || [ -z "$PARTITION_END" ]; then
    echo "ERROR: Could not determine disk or partition size!" | tee -a "$LOG_FILE"
    exit 1
fi

# Ensure values are numeric
if ! [[ "$TOTAL_DISK_SIZE" =~ ^[0-9]+$ ]] || ! [[ "$PARTITION_END" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid size values retrieved. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

UNALLOCATED=$((TOTAL_DISK_SIZE - PARTITION_END))

echo "Disk total size:  $TOTAL_DISK_SIZE bytes" | tee -a "$LOG_FILE"
echo "Partition end:    $PARTITION_END bytes" | tee -a "$LOG_FILE"
echo "Unallocated size: $UNALLOCATED bytes" | tee -a "$LOG_FILE"

# Check if resizing is needed
if (( UNALLOCATED < 1000000 )); then
    echo "Partition already uses full disk space. No resize needed." | tee -a "$LOG_FILE"
else
    echo "Resizing $PARTITION_DEVICE to fill available space..." | tee -a "$LOG_FILE"

    # Safely check if parted supports resizing
    if ! parted "$DISK_DEVICE" print | grep -q "^ $PARTITION_N"; then
        echo "ERROR: Partition $PARTITION_N not found on $DISK_DEVICE!" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Resize the partition
    echo "Running: parted $DISK_DEVICE resizepart $PARTITION_N 100%" | tee -a "$LOG_FILE"
    yes | parted "$DISK_DEVICE" resizepart "$PARTITION_N" 100% 2>&1 | tee -a "$LOG_FILE"

    # Resize the filesystem
    echo "Resizing filesystem on $PARTITION_DEVICE..." | tee -a "$LOG_FILE"
    /sbin/resize2fs "$PARTITION_DEVICE" 2>&1 | tee -a "$LOG_FILE"

    echo "Resize complete! Your filesystem now uses the full MicroSD capacity." | tee -a "$LOG_FILE"
fi

# Disable the service after execution to prevent future runs
echo "Disabling the resize service to prevent re-execution." | tee -a "$LOG_FILE"
/usr/bin/systemctl disable resizefs.service || echo "Warning: Failed to disable the service." | tee -a "$LOG_FILE"

exit 0
