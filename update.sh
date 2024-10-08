#!/bin/bash

set -v

#bash <(curl -s https://raw.githubusercontent.com/Stary/frame/refs/heads/main/install.sh)

if [ "$EUID" -eq 0 ]
  then echo "Please do not run the script as root"
  exit
fi

USER=`whoami`
SRC_DIR="$(cd $(dirname $(realpath "$0")); pwd -P)"
HOME_DIR=`eval echo ~$USER`
MEDIA_DIR="$HOME_DIR/photo"
DEMO_DIR="$HOME_DIR/demo"
CONF_DIR="$HOME_DIR/.config/conky"
BIN_DIR="$HOME_DIR/bin"
LOG_DIR="/var/log/frame"
SSH_DIR=$HOME/.ssh
SSH_KEYS=$SSH_DIR/authorized_keys

CONF="conky.conf"
FONT="UbuntuThin.ttf"
MAIN_SCRIPT="frame_watchdog.sh"
INFO_SCRIPT="get_info.sh"
GEO_SCRIPT="geo.py"
PLACE_SCRIPT="get_place.py"
LOG_FILE="frame.log"

pushd $SRC_DIR
git pull
popd

if [ ! -d "$SSH_DIR" ]
then
  mkdir -p $SSH_DIR
  chmo 700 $SSH_DIR
fi

if [ ! -s "$SSH_KEYS" ]
then
  cat $SRC_DIR/keys.txt >> $SSH_KEYS
  chmod 600 $SSH_KEYS
fi

if [ ! -d "$DEMO_DIR" ]
then
  mkdir $DEMO_DIR
  unzip -d $DEMO_DIR $SRC_DIR/demo.zip
fi

for d in $MEDIA_DIR $DEMO_DIR $CONF_DIR $BIN_DIR $LOG_DIR
do
  echo $d
  sudo mkdir -p $d
  sudo chown -R $USER $d
done

if [ $SRC_DIR != $BIN_DIR ];
then
  rsync -av $SRC_DIR/$MAIN_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$INFO_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$PLACE_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$GEO_SCRIPT $BIN_DIR
  #remove outdated script
  rm -f $BIN_DIR/get_date.sh
fi
rsync -av $SRC_DIR/$CONF $CONF_DIR
rsync -av $SRC_DIR/$FONT $CONF_DIR


(crontab -l 2>/dev/null| grep -v $MAIN_SCRIPT; echo "* * * * * $BIN_DIR/$MAIN_SCRIPT >> $LOG_DIR/$LOG_FILE 2>&1") | crontab -

pkill conky
pkill unclutter
pkill feh

$BIN_DIR/$MAIN_SCRIPT

