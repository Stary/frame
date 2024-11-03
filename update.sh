#!/bin/bash

#bash <(curl -s https://raw.githubusercontent.com/Stary/frame/refs/heads/main/install.sh)

#Проверим, чтобы не был запущен другой экземпляр скрипта
if pidof -o %PPID -x -- "$0" >/dev/null; then
  printf >&2 '%s\n' "ERROR: Script $0 already running"
  exit 1
fi

echo "=================================================================================="
date
echo "----------------------------------------------------------------------------------"


if [ "$EUID" -eq 0 ]
  then echo "Please do not run the script as root"
  exit
fi

set -v 

OPTION=$1

USER=$(whoami)
SRC_DIR="$(cd $(dirname $(realpath "$0")); pwd -P)"
HOME_DIR=$(eval echo ~$USER)

MEDIA_USER=media
MEDIA_PASSWD_FILE=$HOME_DIR/user.dat
MEDIA_DIR=/media

PHOTO_DIR="$MEDIA_DIR/photo"
DEMO_DIR="$MEDIA_DIR/demo"
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

chmod 700 $HOME
chmod 700 $LOG_DIR

if [ -s "$SSH_KEYS" ]
then
  USER=$(whoami)
  echo "Ключи SSH на месте, запрещаем пользователю $USER вход по паролю"
  sudo passwd -d $USER
fi

sudo mkdir -p $MEDIA_DIR
PWDENT=$(getent passwd $MEDIA_USER)
if [ -n "$PWDENT" ]; then
  echo "Пользователь $MEDIA_USER уже существует: $PWDENT"
  sudo usermod -s /usr/sbin/nologin -d $MEDIA_DIR $MEDIA_USER
else
  echo "Создаем пользователя $MEDIA_USER"
  sudo useradd -s /usr/sbin/nologin -d $MEDIA_DIR $MEDIA_USER
fi

if [ -d /etc/ssh/sshd_config.d/ ]
then
  MEDIA_SSH_CONF=/etc/ssh/sshd_config.d/$MEDIA_USER.conf
  sudo touch $MEDIA_SSH_CONF
  sudo chown $MEDIA_USER $MEDIA_SSH_CONF
  echo -e "Match User $MEDIA_USER\n  ForceCommand internal-sftp\n" | sudo tee $MEDIA_SSH_CONF
  sudo systemctl restart ssh
fi

if [ -s $MEDIA_PASSWD_FILE ]
then
  MEDIA_PASSWD=$(cat $MEDIA_PASSWD_FILE)
else
  MEDIA_PASSWD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13; echo)
  echo "$MEDIA_PASSWD" > $MEDIA_PASSWD_FILE
fi

echo -e "$MEDIA_PASSWD\n$MEDIA_PASSWD" | sudo passwd "$MEDIA_USER"

if [ ! -d "$DEMO_DIR" ]
then
  sudo mkdir -p "$DEMO_DIR"
  sudo chown -R $USER "$DEMO_DIR"
  wget -O $TMP_DEMO_ZIP "$STATIC_BASE_URL/$DEMO_ZIP"
  if [ -s "$TMP_DEMO_ZIP" ]
  then
    unzip -d "$DEMO_DIR" $TMP_DEMO_ZIP
    rm -f $TMP_DEMO_ZIP
  else
    rmdir "$DEMO_DIR"
  fi
fi

if [ ! -d "$PHOTO_DIR" ]
then
  sudo mkdir -p "$PHOTO_DIR"
  sudo chown -R $MEDIA_USER "$PHOTO_DIR"
fi

for d in $CONKY_CONF_DIR $BIN_DIR $LOG_DIR
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
  echo 'Через 10 секунд перезагружаюсь'
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
#ToDo: Генерировать пароль в привязке в идентификатору платы
#ToDo: Вынести все настроечные переменные в общий файл


