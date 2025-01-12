#!/bin/bash

VERSION=_VERSION_

f=$1
max_len=$2

ts=''

BIN_DIR=$HOME/bin
USB_DIR=/media/usb
LOCAL_DIR=/media/photo
CONFIG=frame.cfg
MEDIA_USER=media
MEDIA_PASSWD=$(cat ~/user.dat)
IP=$(ifconfig | grep inet | grep -v inet6 | grep -v 127.0.0.1 | sed 's/.*inet *//' | sed 's/ *netmask.*//')
WIFI_SSID=$(sudo nmcli --fields CONNECTION,STATE,DEVICE  d | grep -v -i disconnected | grep -i connected | grep wlan | cut -d ' ' -f 1)
USB_READY=0
if [ $(mount | grep -c $USB_DIR) -gt "0" ] && [ -w "$USB_DIR" ]
then
  USB_READY=1
fi

uptime=$(awk '{print $1}' /proc/uptime | sed 's/\..*//')
changed_files=$(find $BIN_DIR -type f -mmin -5 | grep -v pycache)

if [ "$uptime" -lt "300" ] || [ -n "$changed_files" ]
then
  echo "Фоторамка v.$VERSION"
  echo ""
  if [ "X$USB_READY" != "X1" ]
  then
    echo "Просто вставьте флэшку с фотографиями и наслаждайтесь воспоминаниями!"
    echo ""
    echo "Для стабильной работы флэшку необходимо предварительно отформатировать в FAT32"
    echo "на компьютере под управлением операционной системы Windows 10/11."
    echo ""
    echo "Настройки слайдшоу и часов будут сохранены на флэшке в файле $CONFIG,"
    echo "их можно редактировать как по сети, так и подключив временно флэшку к компьютеру."
    echo ""
  fi

  if [ -z "$IP" ] || [ -z "$WIFI_SSID" ]
  then
    echo "Для подключения рамки к сети создайте на флэшке файл wifi.txt с двумя строками:"
    echo "в первой строке укажите название сети WiFi (стандарта WPA2), во второй - пароль."
  else
    echo "Протокол: SFTP"
    echo "Сеть: $WIFI_SSID"
    echo "IP: $IP"
    echo "Порт: 22"
    echo "Пользователь: $MEDIA_USER"
    echo "Пароль: $MEDIA_PASSWD"
    echo "Папка для фотографий на MicroSD: $LOCAL_DIR"
    if [ "X$USB_READY" == "X1" ]
    then
      echo "Папка с фотографиями на флэшке: $USB_DIR"
      echo "Конфигурационный файл: $USB_DIR/$CONFIG"
    else
      echo "Конфигурационный файл: $LOCAL_DIR/$CONFIG"
    fi
  fi
  exit
fi

export LC_ALL=ru_RU.UTF-8
export LANG=ru_RU.UTF-8

if [ -s "$f" ]
then
  #ts=$(exiftool "$1" 2>/dev/null | grep -i date | grep -i -E -e "(create|gps|original)" | sort | head -1 | sed -E "s/^[^\:]+\:\s*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+).*/\1-\2-\3 \4:\5:\6/")
  ts=$(exiftool "$1" 2>/dev/null | grep -i date | grep -i -E -e "(create|gps|original)" | cut -d ':' -f 2- | sed 's/$/ 00:00:00/' | sort -r | head -1 | sed -E "s/^\s*([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)[^0-9]*.*/\1-\2-\3 \4:\5:\6/")
fi

if [ -z "$ts" ]
then
  ts=$(echo $1 | sed -E "s/^.*\///g" | sed -E "s/\.[^\.]+$//" | grep -E -e "^[0-9_]+$" | sed -E "s/^.*?([0-9]{4})([0-9]{2})([0-9]{2})\_([0-9]{2})([0-9]{2})([0-9]{2}).*$/\1-\2-\3 \4:\5:\6/g")
fi

if [ -n "$ts" ]
then
  ts=$(date --date "$ts" +'%a %d %B %Y %R' 2>/dev/null)
fi

place=$(~/bin/get_place.py "$f" "$max_len")

if [ -n "$ts" ]
then
  echo $ts
fi

if [ -n "$place" ]
then
  echo $place
fi
