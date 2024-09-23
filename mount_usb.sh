#!/bin/bash

MOUNT_FOLDER=/media/usb

mkdir -p $MOUNT_FOLDER

test_file='asDF4)SF4mADf.dat'

touch $MOUNT_FOLDER/$test_file || umount $MOUNT_FOLDER
rm -f $MOUNT_FOLDER/$test_file

for name in `find /dev -name 'sd*1'`
do
  n=`mount | grep $name | wc -l`
  if [ $n -eq 0 ]
  then
    echo "Found external partition $name"
    mount $name $MOUNT_FOLDER || exit -1
    for f in `find  $MOUNT_FOLDER -name '*.txt' -size -256 | grep -i wifi`
    do
      echo $f
      wifi_ssid=""
      wifi_password=""
      for line in `head -10 $f`
      do
        if [ $line != '' ]; then
          echo $line
          if [ "$wifi_ssid" == '' ]; then
            wifi_ssid=$line
            wifi_nm_file="/etc/NetworkManager/system-connections/$wifi_ssid.nmconnection"
          else
            if [ "$wifi_password" == '' ]; then
              wifi_password=$line
              echo "WiFi: $wifi_ssid/$wifi_password"
              nmcli device wifi connect "$wifi_ssid" password "$wifi_password" ifname wlan0
              echo "Created Network Manager config at $wifi_nm_file"
            fi
          fi
        fi
      done
    done
    pkill feh
#  else
#    echo "Partition $name is already mounted"
  fi
done
