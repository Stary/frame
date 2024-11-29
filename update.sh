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
YANDEX_DISK_SYNC_SCRIPT="yd.py"
YANDEX_DISK_DOWNLOAD_SCRIPT="download_yd.sh"
YANDEX_DISK_PUBLIC_URL="https://disk.yandex.ru/d/8Jq0RAsDYAUIww"
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
echo "Version: $VERSION"
popd

cat ~/.bashrc 2>/dev/null| grep -v update.sh > ~/.bashrc.tmp
mv -f ~/.bashrc.tmp ~/.bashrc
echo "alias u='cd ~/frame && git pull && ./update.sh 2>/dev/null | tee -a $LOG_DIR/update.log'" >> ~/.bashrc
source ~/.bashrc

#Отключение IPv6
RANDOM_STR=$(tr -dc A-HJKMNP-Za-hjkmnp-z1-9 </dev/urandom | head -c 8)
ETC_SYSCTL=/etc/sysctl.conf
TMP_SYSCTL=/tmp/$RANDOM_STR

sudo grep -v disable_ipv6 $ETC_SYSCTL > "$TMP_SYSCTL"
sudo sysctl -a | grep disable_ipv6 | sed 's/ *= *0/ = 1/' >> "$TMP_SYSCTL"

if [ -s "$TMP_SYSCTL" ]
then
  sudo cp -f "$TMP_SYSCTL" $ETC_SYSCTL
  rm -f "$TMP_SYSCTL"
  sudo sysctl -p
fi

###############################################

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
  echo "Ключи SSH на месте, запрещаем пользователям $USER и root вход по паролю"
  sudo passwd -d $USER
  sudo passwd -d root
  sudo sed -i -E -e 's/PermitRootLogin\s+yes/PermitRootLogin no/' /etc/ssh/sshd_config
  sudo systemctl reload ssh
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

sudo usermod -g $MEDIA_USER $USER

if [ -d /etc/ssh/sshd_config.d/ ]
then
  MEDIA_SSH_CONF=/etc/ssh/sshd_config.d/$MEDIA_USER.conf
  sudo touch $MEDIA_SSH_CONF
  sudo chown $MEDIA_USER $MEDIA_SSH_CONF
  echo -e "Match User $MEDIA_USER\n  ForceCommand internal-sftp -u 0002\n" | sudo tee $MEDIA_SSH_CONF
  sudo systemctl restart ssh
fi

if [ -s $MEDIA_PASSWD_FILE ]
then
  MEDIA_PASSWD=$(cat $MEDIA_PASSWD_FILE)
else
  MEDIA_PASSWD=$(tr -dc A-HJKMNP-Za-hjkmnp-z1-9 </dev/urandom | head -c 10; echo)
  echo "$MEDIA_PASSWD" > $MEDIA_PASSWD_FILE
fi

echo -e "$MEDIA_PASSWD\n$MEDIA_PASSWD" | sudo passwd "$MEDIA_USER"

if [ ! -d "$DEMO_DIR" ] || [ "$(find "$DEMO_DIR" -type f | wc -l)" -eq 0 ]
then
  sudo mkdir -p "$DEMO_DIR"
  sudo chown -R $USER:$MEDIA_USER "$DEMO_DIR"
  sudo chmod 775 "$DEMO_DIR"
  #wget -O $TMP_DEMO_ZIP "$STATIC_BASE_URL/$DEMO_ZIP"
  $YANDEX_DISK_DOWNLOAD_SCRIPT "$YANDEX_DISK_PUBLIC_URL" "$DEMO_ZIP" "$TMP_DEMO_ZIP"
  if [ -s "$TMP_DEMO_ZIP" ]
  then
    unzip -d "$DEMO_DIR" $TMP_DEMO_ZIP
    rm -f $TMP_DEMO_ZIP
    sudo chmod -R g+rw "$DEMO_DIR"
  else
    rmdir "$DEMO_DIR"
  fi
fi

if [ ! -d "$PHOTO_DIR" ]
then
  sudo mkdir -p "$PHOTO_DIR"
  sudo chown -R $MEDIA_USER:$MEDIA_USER "$PHOTO_DIR"
  sudo chmod 775 "$PHOTO_DIR"
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
  rsync -av $SRC_DIR/$YANDEX_DISK_SYNC_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$YANDEX_DISK_DOWNLOAD_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$WALLPAPER_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$HISTORY_FILE $BIN_DIR
  sed -i "s/_VERSION_/$VERSION/" $BIN_DIR/$HISTORY_FILE
  sed -i "s/_VERSION_/$VERSION/" $BIN_DIR/$MAIN_SCRIPT
  sed -i "s/_VERSION_/$VERSION/" $BIN_DIR/$INFO_SCRIPT
  iconv -f UTF-8 -t WINDOWS-1251 -o $BIN_DIR/$HISTORY_WIN_FILE $BIN_DIR/$HISTORY_FILE
  unix2dos $BIN_DIR/$HISTORY_WIN_FILE
  if [ -s $USB_DIR/$HISTORY_FILE ]
  then
    cp -f $BIN_DIR/$HISTORY_FILE $USB_DIR
    cp -f $BIN_DIR/$HISTORY_WIN_FILE $USB_DIR
    #Удаление файла истории изменений со старым именем
    rm -f $USB_DIR/changes*.txt
  fi
  #remove outdated script
  rm -f $BIN_DIR/get_date.sh
fi
rsync -av $SRC_DIR/$CONKY_CONF_TEMPLATE $CONKY_CONF_DIR
rsync -av $SRC_DIR/$CONKY_FONT $CONKY_CONF_DIR

##################################################################
#Обновление логотипа

target_logo_file='/usr/share/plymouth/themes/orangepi/watermark.png'
target_logo_md5=$(md5sum "$target_logo_file" | cut -d ' ' -f 1)

#source_url='https://quietharbor.net/static/watermark.png'
source_logo_file='watermark.png'
source_logo_md5='bf7c2d23aa96006dc8e4cedb44c93bf1'

tmp_file='/tmp/watermark.png'

#scp -P 57093 watermark.png root@quietharbor.net:/var/www/quietharbor.net/static
#

if [ "X$source_logo_md5" != "X$target_logo_md5" ]
then
  echo "Source MD5: $source_logo_md5 != Target MD5: $target_logo_md5"
  #wget -O "$tmp_file" "$source_url"
  $YANDEX_DISK_DOWNLOAD_SCRIPT "$YANDEX_DISK_PUBLIC_URL" "$source_logo_file" "$tmp_file"
  tmp_md5=$(md5sum "$tmp_file" | cut -d ' ' -f 1)
  if [ "X$tmp_md5" == "X$source_logo_md5" ]
  then
    echo "Скачан корректный файл с логотипом, обновляем"
    sudo cp -f $tmp_file $target_logo_file
    sudo update-initramfs -u
  fi
else
  echo "Логотип актуальный, обновление не требуется"
fi

source_blackbg_file='blackbg.png'
target_blackbg_file="$USER/blackbg.png"

if [ ! -s "$target_blackbg_file" ]
then
  echo "Скачиваем файл с черным фоном"
  $YANDEX_DISK_DOWNLOAD_SCRIPT "$YANDEX_DISK_PUBLIC_URL" "$source_blackbg_file" "$target_blackbg_file"
  echo "$YANDEX_DISK_DOWNLOAD_SCRIPT $YANDEX_DISK_PUBLIC_URL $source_blackbg_file $target_blackbg_file"
fi

if [ -s "$target_blackbg_file" ]
then
  $BIN_DIR/$WALLPAPER_SCRIPT "$target_blackbg_file" 5
fi

if [ -f "$target_logo_file" ]
then
  $BIN_DIR/$WALLPAPER_SCRIPT "$target_logo_file" 1
fi

########################################################################
#Включение ежеминутного запуска контрольного скрипта

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
  pkill -f feh
  #$BIN_DIR/$WALLPAPER_SCRIPT "$DEMO_DIR"
  $BIN_DIR/$MAIN_SCRIPT
fi

#ToDo: Генерировать пароль в привязке к идентификатору платы
#ToDo: Вынести все настроечные переменные в общий файл
#ToDo: Загружать конфиг построчным чтением файла и инициализацией переменных


