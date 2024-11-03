#!/bin/bash

VERSION=_VERSION_

f=$1
max_len=$2

ts=''

export LC_ALL=ru_RU.UTF-8
export LANG=ru_RU.UTF-8

BIN_DIR=$HOME/bin
MEDIA_USER=media
MEDIA_PASSWD=$(cat ~/user.dat)
IP=$(ifconfig | grep inet | grep -v inet6 | grep -v 127.0.0.1 | sed 's/.*inet *//' | sed 's/ *netmask.*//')

uptime=$(awk '{print $1}' /proc/uptime | sed 's/\..*//')
changed_files=$(find $BIN_DIR -type f -mmin -5)
if [ "$uptime" -lt "300" ] || [ -n "$changed_files" ]
then
  echo "Фоторамка v.$VERSION"
  echo "Просто подключите флэшку с фотографиями и наслаждайтесь воспоминаниями!"
  echo "Настройки слайдшоу и часов будут сохранены на флэшке, их можно редактировать."
  echo "Протокол: SCP, IP: $IP, пользователь: $MEDIA_USER, пароль: $MEDIA_PASSWD"
  echo "Флэшка: /media/usb, папка для фотографий на встроенном MicroSD - /media/photo"
  #echo "+7 999 999-99-99"
  #echo "https://тут_будет_адрес_сайта.com"
  exit
fi

if [ -s "$f" ]
then
  ts=$(exiftool "$1" 2>/dev/null | grep -i date | grep -i -E -e "(create|gps|original)" | sort | head -1 | sed -E "s/^[^\:]+\:\s*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+).*/\1-\2-\3 \4:\5:\6/")
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
