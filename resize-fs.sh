#!/bin/sh
set -e

# Log to kernel messages
log() {
    echo "resizefs: $*" > /dev/kmsg
}

log "========== Resize Root Partition Script =========="
log "Started at $(date)"

# Check if tools are available
for cmd in parted resize2fs blkid e2fsck dumpe2fs; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "ERROR: Command '$cmd' not found in initramfs!"
        exit 1
    fi
done

# Get root device from kernel command line
ROOT_SPEC=$(cat /proc/cmdline | grep -o 'root=[^ ]*' | sed 's/root=//')
if [ -z "$ROOT_SPEC" ]; then
    log "ERROR: Could not determine root device from /proc/cmdline!"
    exit 1
fi
log "Root spec from cmdline: $ROOT_SPEC"

# Dump full cmdline for debugging
log "Full /proc/cmdline: $(cat /proc/cmdline)"

# Resolve UUID to device path if necessary
if echo "$ROOT_SPEC" | grep -q "^UUID="; then
    UUID=$(echo "$ROOT_SPEC" | sed 's/^UUID=//')
    log "Extracted UUID: $UUID"
    ROOT_DEV=$(blkid | grep "$UUID" | cut -d: -f1)
    if [ -z "$ROOT_DEV" ]; then
        log "ERROR: Could not resolve UUID $UUID to a device!"
        log "blkid output: $(blkid)"
        exit 1
    fi
    log "Resolved UUID $UUID to device: $ROOT_DEV"
else
    ROOT_DEV="$ROOT_SPEC"
    log "Using direct root device: $ROOT_DEV"
fi

# Extract disk and partition number
case "$ROOT_DEV" in
    /dev/mmcblk*p*)
        DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
        PART_N=$(echo "$ROOT_DEV" | sed 's/.*p//')
        PART="$ROOT_DEV"
        ;;
    *)
        log "ERROR: Unsupported root device format: $ROOT_DEV"
        exit 1
        ;;
esac

log "Detected disk: $DISK"
log "Detected partition: $PART"
log "Partition number: $PART_N"

# Check if disk exists
if [ ! -b "$DISK" ]; then
    log "ERROR: Disk $DISK not found!"
    exit 1
fi

# Dump parted output for debugging
log "Running: parted $DISK unit B print"
parted "$DISK" unit B print > /tmp/parted_output 2>&1
cat /tmp/parted_output > /dev/kmsg
rm -f /tmp/parted_output

# Get partition sizes in bytes
TOTAL_DISK_SIZE=$(parted "$DISK" unit B print | awk '/Disk \/dev/{print $3}' | sed 's/B//g')
PARTITION_END=$(parted "$DISK" unit B print | awk "/^ *$PART_N /{print \$3}" | sed 's/B//g')
PARTITION_START=$(parted "$DISK" unit B print | awk "/^ *$PART_N /{print \$2}" | sed 's/B//g')

log "Raw TOTAL_DISK_SIZE: '$TOTAL_DISK_SIZE'"
log "Raw PARTITION_END: '$PARTITION_END'"
log "Raw PARTITION_START: '$PARTITION_START'"

if [ -z "$TOTAL_DISK_SIZE" ] || [ -z "$PARTITION_END" ] || [ -z "$PARTITION_START" ]; then
    log "ERROR: Could not determine disk or partition size!"
    exit 1
fi

PARTITION_SIZE=$((PARTITION_END - PARTITION_START + 1))
UNALLOCATED=$((TOTAL_DISK_SIZE - PARTITION_END))

log "Partition size: $PARTITION_SIZE bytes"
log "Disk total size: $TOTAL_DISK_SIZE bytes"
log "Partition end: $PARTITION_END bytes"
log "Unallocated size: $UNALLOCATED bytes"

# Get filesystem size in bytes
FS_BLOCK_COUNT=$(dumpe2fs -h "$PART" 2>/dev/null | grep "^Block count:" | awk '{print $3}')
FS_BLOCK_SIZE=$(dumpe2fs -h "$PART" 2>/dev/null | grep "^Block size:" | awk '{print $3}')
if [ -z "$FS_BLOCK_COUNT" ] || [ -z "$FS_BLOCK_SIZE" ]; then
    log "ERROR: Could not determine filesystem size with dumpe2fs!"
    exit 1
fi
FS_SIZE=$((FS_BLOCK_COUNT * FS_BLOCK_SIZE))
log "Filesystem size: $FS_SIZE bytes"

# Check if resizing is needed
if [ "$UNALLOCATED" -lt 1000000 ] && [ "$FS_SIZE" -ge "$PARTITION_SIZE" ]; then
    log "Partition and filesystem already use full disk space. No resize needed."
else
    # Resize partition if unallocated space exists
    if [ "$UNALLOCATED" -ge 1000000 ]; then
        log "Resizing $PART to fill available space..."
        if ! parted -s "$DISK" resizepart "$PART_N" 100%; then
            log "ERROR: Failed to resize partition $PART_N on $DISK!"
            exit 1
        fi
        sleep 1
        PARTITION_SIZE=$((TOTAL_DISK_SIZE - PARTITION_START + 1))
        log "Partition resized to: $PARTITION_SIZE bytes"
    fi

    # Check and resize filesystem if smaller than partition
    if [ "$FS_SIZE" -lt "$PARTITION_SIZE" ]; then
        log "Checking filesystem on $PART..."
        if ! e2fsck -f -y "$PART" > /tmp/e2fsck_output 2>&1; then
            log "ERROR: e2fsck failed on $PART!"
            cat /tmp/e2fsck_output > /dev/kmsg
            rm -f /tmp/e2fsck_output
            exit 1
        fi
        cat /tmp/e2fsck_output > /dev/kmsg
        rm -f /tmp/e2fsck_output
        log "Filesystem check complete."

        log "Resizing filesystem on $PART..."
        if ! resize2fs "$PART" > /tmp/resize2fs_output 2>&1; then
            log "ERROR: Failed to resize filesystem on $PART!"
            cat /tmp/resize2fs_output > /dev/kmsg
            rm -f /tmp/resize2fs_output
            exit 1
        fi
        cat /tmp/resize2fs_output > /dev/kmsg
        rm -f /tmp/resize2fs_output
        log "Resize complete! Filesystem now uses full MicroSD capacity."
    else
        log "Filesystem already matches partition size. No resize needed."
    fi
fi

log "Script completed successfully."
exit 0
