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

rm -f -v $MOUNT_POINT/var/log/frame/*
rm -f -v $MOUNT_POINT/var/log/resize*
rm -f -v $MOUNT_POINT/home/orangepi/user.dat
rm -f -v $MOUNT_POINT/etc/systemd/system/resizefs.service
rm -f -v $MOUNT_POINT/usr/local/bin/resize_root.sh

umount $MOUNT_POINT

e2fsck -f $PARTITION_DEVICE
resize2fs $PARTITION_DEVICE $IMAGE_SIZE

parted $DISK_DEVICE resizepart $PARTITION_NUM $IMAGE_SIZE
parted $DISK_DEVICE print

resize2fs $PARTITION_DEVICE

e2fsck -f $PARTITION_DEVICE

#dd if=$DISK_DEVICE bs=512 count=11 status=progress | gzip > frame.$TS.gz