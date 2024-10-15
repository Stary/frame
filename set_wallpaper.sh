#!/bin/bash

if [ "$DISPLAY" == "" ]; then
  export DISPLAY=:0
fi

if [ -d "$1" ]; then
  bgimage=$(find $1 -type f -size +100k | grep -i -E -e '(img|png|jpg|jpeg)' | shuf -n 1)
else
  bgimage=$1
fi

if [ "$bgimage" != "" ] && [ -s "$bgimage" ]
then
  echo Changing background to $bgimage

  for p in $(xfconf-query -c xfce4-desktop -l | grep -i last-image)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s "$bgimage"
  done
  for p in $(xfconf-query -c xfce4-desktop -l | grep -i image-stype)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s 5
  done
fi

unclutter_running=$(pgrep -c unclutter)
if [ -z "$unclutter_running" ]; then
  echo $unclutter_running
  pgrep unclutter
  unclutter -root 2>&1 >/dev/null &
fi

xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 2
xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-style -s 1
xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/leave-opacity -s 0
xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/enter-opacity -s 0
#xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-rgba -s 0

xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -s 0
xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-sleep -s 0
xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -s 0


