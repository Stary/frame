#!/bin/bash

DAY=800
NIGHT=2400

IMAGES_DIR=/home/orangepi/frame

if [ -d ~/photo ]
then
  IMAGES_DIR=~/photo
fi

USB_DIR=/media/usb

export DISPLAY=:0.0
export XAUTHORITY=/home/orangepi/.Xauthority

#exiftran -ai $IMAGES_DIR/*


###################### Mount USB ####################

sudo mkdir -p $USB_DIR

test_file='asDF4)SF4mADf.dat'

sudo touch $USB_DIR/$test_file || sudo umount $USB_DIR
sudo rm -f $USB_DIR/$test_file

for name in `find /dev -name 'sd*1'`
do
  n=`mount | grep $name | wc -l`
  if [ $n -eq 0 ]
  then
    echo "Found external partition $name"
    if sudo mount $name $USB_DIR; then
      for f in `find  $USB_DIR -name '*.txt' -size -256 | grep -i wifi`
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
                sudo nmcli device wifi connect "$wifi_ssid" password "$wifi_password" ifname wlan0
                echo "Created Network Manager config at $wifi_nm_file"
              fi
            fi
          fi
        done
      done
    fi
    pkill feh
#  else
#    echo "Partition $name is already mounted"
  fi
done

#####################################################


shopt -s extglob
TIME=`date +%H%M | sed 's/^0\{1,3\}//'`

NTP=`chronyc tracking | grep -i status | grep -i normal | wc -l`

if (( $NTP == 0 ))
then
  echo "Синхронизация с NTP не работает, включаем принудительный дневной режим"
  TIME=$DAY
fi

if (( $TIME >= $DAY && $TIME < $NIGHT ))
then
#  pkill dclock
  pkill conky
  pkill unclutter


  PID=`pgrep exiftran`
  if [ ! -z "$PID" ]
  then
    echo "Exiftran is running, exiting"
    exit 0
  fi

  PID=`pgrep feh`
  if [ -z "$PID" ]
  then
    date
    echo "Переход в дневной режим - запуск рамки"
    usb_images=`find $USB_DIR -size +100k | grep -i -E -e "(img|png)" | wc -l`

    if (( $usb_images > 0 ))
    then
      echo "Найдено $usb_images графических файлов на внешнем носителе $USB_DIR, переключаемся на него"
      IMAGES_DIR=$USB_DIR
    fi

    sudo chown -R orangepi $IMAGES_DIR 2>/dev/null
    sudo find $IMAGES_DIR -type f -not -empty -exec exiftran -ai '{}' \;  2>/dev/null
    #/usr/bin/feh -r -z -q -p -Z -F -Y -D 55.0 $IMAGES_DIR || exit -1 &
#    feh -r -q -F -Y -D 15.0 -S name --start-at `find $IMAGES_DIR -size +1M | shuf | head -1` $IMAGES_DIR || exit -1 &
    feh -r -q -F -Y -D 15.0 -S name --start-at `find $IMAGES_DIR -size +1M | shuf | head -1` --info 'echo %F | sed -E "s/^.*+\///g" | sed -E "s/\.[^\.]+$//" | sed -E "s/^.*?([0-9]{4})([0-9]{2})([0-9]{2})\_[0-9]+.*$/\1.\2.\3/g"' $IMAGES_DIR || exit -1 &

  fi
else
  pkill feh
#  PID=`pgrep dclock`
  PID=`pgrep conky`
  if [ -z "$PID" ]
  then
    date
    echo "Переход в ночной режим - запуск часов"
    #Конфигурация часов сохранена в файле /home/pi/.config/conky/conky.conf
    conky
#    dclock -nobell -miltime -tails -noscroll -blink -nofade -noalarm -thickness 0.12 -slope 70.0 -bd "black" -bg "black" -fg "darkorange" -led_off "black" &
    sleep 2s
    unclutter -root 2>&1 >/dev/null &
#    wmctrl -r dclock -b add,fullscreen,above
  fi
  wmctrl -r conky -b add,fullscreen,above
fi

