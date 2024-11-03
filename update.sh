#!/bin/bash

#bash <(curl -s https://raw.githubusercontent.com/Stary/frame/refs/heads/main/install.sh)

echo "=================================================================================="
date
echo "----------------------------------------------------------------------------------"


if [ "$EUID" -eq 0 ]
  then echo "Please do not run the script as root"
  exit
fi

set -v 

OPTION=$1

USER=`whoami`
SRC_DIR="$(cd $(dirname $(realpath "$0")); pwd -P)"
HOME_DIR=`eval echo ~$USER`
MEDIA_DIR="$HOME_DIR/photo"
DEMO_DIR="$HOME_DIR/demo"
DEMO_ZIP="demo.zip"
TMP_DEMO_ZIP="/tmp/$DEMO_ZIP"
CONKY_CONF_DIR="$HOME_DIR/.config/conky"
BIN_DIR="$HOME_DIR/bin"
LOG_DIR="/var/log/frame"
SSH_DIR=$HOME/.ssh
USB_DIR="/media/usb"
SSH_KEYS=$SSH_DIR/authorized_keys
STATIC_BASE_URL="https://quietharbor.net/static/"

CONKY_CONF_TEMPLATE="conky.conf.template"
CONKY_FONT="UbuntuThin.ttf"
MAIN_SCRIPT="frame_watchdog.sh"
INFO_SCRIPT="get_info.sh"
GEO_SCRIPT="geo.py"
PLACE_SCRIPT="get_place.py"
WALLPAPER_SCRIPT="set_wallpaper.sh"
UPDATE_SCRIPT="update.sh"
VERSION_SCRIPT="get_version.sh"
HISTORY_FILE="history.txt"
HISTORY_WIN_FILE="history.win.txt"
LOG_FILE="frame.log"

pushd $SRC_DIR
git_status=$(git status)
echo "status: $git_status"
pull_result=$(git pull)
echo "|$pull_result|$?|"
VERSION=$($SRC_DIR/$VERSION_SCRIPT)
popd

cat ~/.bashrc 2>/dev/null| grep -v update.sh > ~/.bashrc.tmp
mv -f ~/.bashrc.tmp ~/.bashrc
echo "alias u='cd ~/frame && git pull && ./update.sh 2>/dev/null | tee -a $LOG_DIR/update.log'" >> ~/.bashrc
source ~/.bashrc

if [ ! -d "$SSH_DIR" ]
then
  mkdir -p $SSH_DIR
  chmod 700 $SSH_DIR
fi

if [ ! -s "$SSH_KEYS" ]
then
  cat $SRC_DIR/keys.txt >> $SSH_KEYS
  chmod 600 $SSH_KEYS
fi

if [ -s "$SSH_KEYS" ]
then
  echo "Ключи SSH на месте, запрещаем вход по паролю"
  sudo passwd -d `whoami`
fi

if [ ! -d "$DEMO_DIR" ]
then
  mkdir -p "$DEMO_DIR"
  wget -O $TMP_DEMO_ZIP "$STATIC_BASE_URL/$DEMO_ZIP"
  if [ -s "$TMP_DEMO_ZIP" ]
  then
    unzip -d "$DEMO_DIR" $TMP_DEMO_ZIP
    rm -f $TMP_DEMO_ZIP
  else
    rmdir "$DEMO_DIR"
  fi
fi

for d in $MEDIA_DIR $DEMO_DIR $CONKY_CONF_DIR $BIN_DIR $LOG_DIR
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
  rsync -av $SRC_DIR/$WALLPAPER_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$HISTORY_FILE $BIN_DIR
  sed -i "s/_VERSION_/$VERSION/" $BIN_DIR/$HISTORY_FILE
  sed -i "s/_VERSION_/$VERSION/" $BIN_DIR/$MAIN_SCRIPT
  sed -i "s/_VERSION_/$VERSION/" $BIN_DIR/$INFO_SCRIPT
  iconv -f UTF-8 -t WINDOWS-1251 -o $BIN_DIR/$HISTORY_WIN_FILE $BIN_DIR/$HISTORY_FILE
  unix2dos $BIN_DIR/$HISTORY_WIN_FILE
  if [ -s $USB_DIR/$HISTORY_FILE ]
  then
    rsync -av $BIN_DIR/$HISTORY_FILE $USB_DIR
    rsync -av $BIN_DIR/$HISTORY_WIN_FILE $USB_DIR
    #Удаление файла истории изменений со старым именем
    rm -f $USB_DIR/changes*.txt
  fi
  #remove outdated script
  rm -f $BIN_DIR/get_date.sh
fi
rsync -av $SRC_DIR/$CONKY_CONF_TEMPLATE $CONKY_CONF_DIR
rsync -av $SRC_DIR/$CONKY_FONT $CONKY_CONF_DIR


#(crontab -l 2>/dev/null| grep -v $UPDATE_SCRIPT; echo "@reboot $SRC_DIR/$UPDATE_SCRIPT norestart >> $LOG_DIR/$LOG_FILE 2>&1") | crontab -
(crontab -l 2>/dev/null| grep -v $UPDATE_SCRIPT) | crontab -
(crontab -l 2>/dev/null| grep -v $MAIN_SCRIPT; echo "* * * * * $BIN_DIR/$MAIN_SCRIPT >> $LOG_DIR/$LOG_FILE 2>&1") | crontab -

if [ "X$OPTION" == "Xnorestart" ]
then
  exit
fi

if [ -f /var/run/reboot-required ]; then
  echo 'Reboot required. Restarting in 10 seconds'
  sleep 10
  sudo reboot
fi


changed_files=$(find "$BIN_DIR" -mtime -1 -type f | grep -v .git | grep -v pycache | wc -l)
if [ "$changed_files" -ne 0 ] || [ "X$OPTION" == "Xforce" ]
then
  echo "$changed_files file(s) were updated, so restarting the service"
  pkill conky
  pkill unclutter
  pkill feh
  $BIN_DIR/$WALLPAPER_SCRIPT "$DEMO_DIR"
  $BIN_DIR/$MAIN_SCRIPT
fi

#ToDo: Эксперимент с разными пользователями media и orangepi
#ToDo: Создание пользователя media с ограничением chroot в /media
#ToDo: Перенос папок в /media
#ToDo: Инструкция по подключению пользователем media


