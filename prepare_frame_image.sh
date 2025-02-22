#!/bin/bash

set -v

PARTITION_DEVICE=/dev/sdc1
DISK_DEVICE=/dev/sdc
PARTITION_NUM=1
MOUNT_POINT=/mnt/frame
IMAGE_SIZE=8G
TS=$(date +%Y%m%d)

set -e

if [ "$EUID" -ne 0 ]; then
  echo "This script requires root privileges, run it with sudo"
  exit 1
fi

mkdir -p $MOUNT_POINT
umount $MOUNT_POINT 2>/dev/null || :

e2fsck -f $PARTITION_DEVICE
resize2fs $PARTITION_DEVICE

mount $PARTITION_DEVICE $MOUNT_POINT
# Remove user-specific, temporary and obsolete files
rm -f -v $MOUNT_POINT/var/log/frame/*
rm -f -v $MOUNT_POINT/var/log/resize*
rm -f -v $MOUNT_POINT/home/orangepi/user.dat
rm -f -v $MOUNT_POINT/etc/systemd/system/resizefs.service
rm -f -v $MOUNT_POINT/usr/local/bin/resize_root.sh
rm -f -v $MOUNT_POINT/root/.bash_history
rm -f -v $MOUNT_POINT/home/orangepi/.bash_history
umount $MOUNT_POINT

e2fsck -f $PARTITION_DEVICE
resize2fs $PARTITION_DEVICE $IMAGE_SIZE

parted $DISK_DEVICE resizepart $PARTITION_NUM $IMAGE_SIZE
parted $DISK_DEVICE print

resize2fs $PARTITION_DEVICE

e2fsck -f $PARTITION_DEVICE

# Calculate sectors to dump (end of partition + buffer)
END_SECTOR=$(parted $DISK_DEVICE unit s print | grep "^ *$PARTITION_NUM" | awk '{print $3}' | sed 's/s$//')
if [ -z "$END_SECTOR" ]; then
  echo "Error: Could not determine end sector of partition $PARTITION_NUM"
  exit 1
fi
BUFFER_SECTORS=2048  # ~1MB buffer
SECTORS_COUNT=$((END_SECTOR + BUFFER_SECTORS))
echo "Dumping $SECTORS_COUNT sectors from $DISK_DEVICE..."

# Create the compressed image
dd if=$DISK_DEVICE bs=512 count=$SECTORS_COUNT status=progress | gzip > frame.$TS.gz

echo "Image created: frame.$TS.gz"
