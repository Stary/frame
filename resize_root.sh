#!/bin/bash
set -e

DEVICE=$(lsblk -no pkname $(findmnt -n -o SOURCE /))  # Find the main device
ROOT_PART=$(lsblk -no PARTNUM $(findmnt -n -o SOURCE /))  # Get root partition number

echo "Resizing /dev/${DEVICE}${ROOT_PART} to fill available space..."

# Resize the partition
echo sudo parted /dev/$DEVICE resizepart $ROOT_PART 100% --script

# Resize the filesystem
echo sudo e2fsck -f /dev/${DEVICE}${ROOT_PART}
echo sudo resize2fs /dev/${DEVICE}${ROOT_PART}

echo "Resize complete! Your filesystem now uses the full MicroSD capacity."