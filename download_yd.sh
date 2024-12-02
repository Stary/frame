#!/bin/bash

# Check if the correct number of arguments is provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <Yandex Disk public folder link> <filename> [result_path_filename]"
    exit 1
fi

FOLDER_LINK=$1
FILENAME=$2
TARGET_PATH=$3

if [ -z "$TARGET_PATH" ]
then
  TARGET_PATH=$FILENAME
fi

# Step 1: Get the metadata for the specific file within the public folder
METADATA=$(wget -qO- "https://cloud-api.yandex.net/v1/disk/public/resources?public_key=$FOLDER_LINK&path=/$FILENAME")

# Check if metadata was successfully retrieved
if [ -z "$METADATA" ] || echo "$METADATA" | grep -q '"error"'; then
    echo "Error: Failed to retrieve metadata. Please check the folder link and filename."
    exit 1
fi

# Step 2: Extract the download URL for the file
DOWNLOAD_URL=$(echo "$METADATA" | grep -oP '"file":"\K[^"]+')

# If download URL is not found, show an error
if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: File '$FILENAME' not found in the folder."
    exit 1
fi

TEMP_PATH="${TARGET_PATH}.tmp"

if [ -s "$TARGET_PATH" ]; then
    LOCAL_MD5=$(md5sum "$TARGET_PATH" | cut -d ' ' -f 1)
    REMOTE_MD5=$(echo "$METADATA" | grep -oP '"md5":"\K[^"]+')
    if [ "X$REMOTE_MD5" == "X$LOCAL_MD5" ]; then
        echo "File $FILENAME has already been downloaded, as its md5 matches the remote one, no need to download it again."
        exit 0
    else
        echo "File $FILENAME found at $TARGET_PATH, but its md5 differs from the remote one. Downloading again."
    fi
fi

echo "Downloading file: $FILENAME"
wget -O "$TEMP_PATH" "$DOWNLOAD_URL"

if [ $? -eq 0 ]; then
    DOWNLOADED_MD5=$(md5sum "$TEMP_PATH" | cut -d ' ' -f 1)
    if [ "X$REMOTE_MD5" == "X$DOWNLOADED_MD5" ]; then
        mv "$TEMP_PATH" "$TARGET_PATH"
        echo "Download completed successfully: $TARGET_PATH"
    else
        echo "Error: Downloaded file's MD5 does not match the expected MD5."
        rm "$TEMP_PATH"
        exit 1
    fi
else
    echo "Error: Failed to download the file."
    rm -f "$TEMP_PATH"
    exit 1
fi