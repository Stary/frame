#!/bin/bash

if [ "X$DISPLAY" == "X" ]; then
  export DISPLAY=:0
fi

if [ -d "$1" ]; then
  bgimage=$(find $1 -type f -size +100k | grep -i -E -e '(img|png|jpg|jpeg)' | shuf -n 1)
else
  bgimage=$1
fi


if [ -n "$2" ]; then
  IMAGE_STYLE=$2
else
  #IMAGE_STYLE=$(xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-style -s)
  #1 - centered
  #2 - tiled
  #3 - fit
  #4 - stretched
  #5 - zoom
  IMAGE_STYLE=5
fi

if [ "$bgimage" != "" ] && [ -s "$bgimage" ]
then
  echo Changing background to "$bgimage"

  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus

  for p in $(xfconf-query -c xfce4-desktop -l | grep -i color-style)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s 0
  done
  for p in $(xfconf-query -c xfce4-desktop -l | grep -i single-workspace-mode)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s false
  done
  for p in $(xfconf-query -c xfce4-desktop -l | grep -i color-style)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s 3
  done
  for p in $(xfconf-query -c xfce4-desktop -l | grep -i single-workspace-mode)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s true
  done

  for p in $(xfconf-query -c xfce4-desktop -l | grep -i last-image)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s "$bgimage"
  done
  for p in $(xfconf-query -c xfce4-desktop -l | grep -i image-style)
  do
    xfconf-query -c xfce4-desktop -p "$p" -s $IMAGE_STYLE
  done
  for p in $(xfconf-query -c xfce4-desktop -l | grep -i rgba1)
  do
    xfconf-query -c xfce4-desktop -p "$p" -t uint -s 0
  done


fi

#unclutter_pid=$(pgrep unclutter)
#if [ -z "$unclutter_pid" ]; then
#  unclutter -root >/dev/null 2>&1 &
#fi

#xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 2
#xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-style -s 1
#xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/leave-opacity -s 0
#xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/enter-opacity -s 0
##xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-rgba -s 0

#xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -s 0
#xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-sleep -s 0
#xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -s 0

#xfconf-query --create -t int  -c xfce4-desktop -p /desktop-icons/style -s 0


