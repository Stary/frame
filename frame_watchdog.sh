#!/bin/bash

#apt-get install feh conky unclutter wmctrl exiftran exif exifprobe
#systemctl enable chrony
#systemctl start chrony
#systemctl enable cron
#systemctl start cron


DAY=800
NIGHT=2400

IMAGES_DIR=/home/orangepi/frame
USB_DIR=/media/usb

export DISPLAY=:0.0
export XAUTHORITY=/home/orangepi/.Xauthority

#exiftran -ai $IMAGES_DIR/*

sudo ~/mount_usb.sh


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
    /usr/bin/feh -r -z -q -p -Z -F -Y -D 55.0 $IMAGES_DIR || exit -1 &
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

