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

notify-send -t 10000 "Запускаю обновление"

OPTION=$1

USER=$(whoami)
SRC_DIR="$(cd $(dirname $(realpath "$0")); pwd -P)"
HOME_DIR=$(eval echo ~$USER)

MEDIA_USER=media
MEDIA_PASSWD_FILE=$HOME_DIR/user.dat
MEDIA_DIR=/media

# Email configuration
# To get Yandex app password:
# 1. Go to https://id.yandex.ru/security/app-passwords
# 2. Click "Create new password"
# 3. Select "Mail" and your device
# 4. Add to ~/frame.cfg: YANDEX_MAIL_APP_PASSWORD=your_password
#    (or set YANDEX_MAIL_APP_PASSWORD= to disable email notifications)
REPORTS_EMAIL='sergey.s.alekseev@yandex.ru'
FRAME_CONFIG_FILE=$HOME_DIR/frame.cfg
ENABLE_EMAIL=0

if [ -f "$FRAME_CONFIG_FILE" ]; then
    # Check if password is configured (even if empty)
    if grep -E "^[[:space:]]*YANDEX_MAIL_APP_PASSWORD=" "$FRAME_CONFIG_FILE" | grep -v "^#"; then
        # Get password value
        REPORTS_APP_PASSWD=$(grep -E "^[[:space:]]*YANDEX_MAIL_APP_PASSWORD=" "$FRAME_CONFIG_FILE" | grep -v "^#" | tail -n1 | cut -d'=' -f2)
        if [ ! -z "$REPORTS_APP_PASSWD" ]; then
            ENABLE_EMAIL=1
        else
            echo "Note: YANDEX_MAIL_APP_PASSWORD is empty in $FRAME_CONFIG_FILE, email notifications are disabled"
        fi
    else
        echo "Note: YANDEX_MAIL_APP_PASSWORD not found in $FRAME_CONFIG_FILE"
        echo "Email notifications are disabled"
    fi
else
    echo "Note: Configuration file not found at $FRAME_CONFIG_FILE"
    echo "Email notifications are disabled. To enable, please follow these steps:"
    echo "1. Go to https://id.yandex.ru/security/app-passwords"
    echo "2. Click 'Create new password'"
    echo "3. Select 'Mail' and your device"
    echo "4. Add to $FRAME_CONFIG_FILE: YANDEX_MAIL_APP_PASSWORD=your_password"
fi

PHOTO_DIR="$MEDIA_DIR/photo"
DEMO_DIR="$MEDIA_DIR/demo"
DEMO_ZIP="demo.zip"
TMP_DEMO_ZIP="/tmp/$DEMO_ZIP"
CONKY_CONF_DIR="$HOME_DIR/.config/conky"
BIN_DIR="$HOME_DIR/bin"
LOG_DIR="/var/log/frame"
SSH_DIR=$HOME_DIR/.ssh
USB_DIR="/media/usb"
SSH_KEYS=$SSH_DIR/authorized_keys

INITRAMFS_SCRIPTS_DIR="/etc/initramfs-tools/scripts/local-premount"
INITRAMFS_HOOKS_DIR="/etc/initramfs-tools/hooks"
INITRAMFS_RESIZE_SCRIPT="resize-fs.sh"
INITRAMFS_TOOLS_SCRIPT="resize-tools"

CONKY_CONF_TEMPLATE="conky.conf.template"
CONKY_FONT="UbuntuThin.ttf"
SYSTEM_FONT_DIR="/usr/share/fonts/truetype/ubuntu"
MAIN_SCRIPT="frame_watchdog.sh"
INFO_SCRIPT="get_info.sh"
GEO_SCRIPT="geo.py"
PLACE_SCRIPT="get_place.py"
TM_SCRIPT="tm.sh"
YANDEX_DISK_SYNC_SCRIPT="yd.py"
YANDEX_DISK_DOWNLOAD_SCRIPT="download_yd.sh"
YANDEX_DISK_PUBLIC_URL="https://disk.yandex.ru/d/8Jq0RAsDYAUIww"
WALLPAPER_SCRIPT="set_wallpaper.sh"
UPDATE_SCRIPT="update.sh"
VERSION_SCRIPT="get_version.sh"
HISTORY_FILE="history.txt"
HISTORY_WIN_FILE="history.win.txt"
LOG_FILE="frame.log"


sudo apt-get update -y
sudo apt-get install -y zip
sudo apt-get autoremove -y

sudo setcap cap_net_raw+p $(which ping)

pushd $SRC_DIR
git_status=$(git status)
echo "status: $git_status"
pull_result=$(git pull)
echo "|$pull_result|$?|"
VERSION=$($SRC_DIR/$VERSION_SCRIPT)
echo "Version: $VERSION"
popd

cat ~/.bashrc 2>/dev/null| grep -v update.sh | grep -v $LOG_FILE > ~/.bashrc.tmp
mv -f ~/.bashrc.tmp ~/.bashrc
echo "alias u='cd ~/frame && git pull && ./update.sh 2>/dev/null | tee -a $LOG_DIR/update.log'" >> ~/.bashrc
echo "alias fl='tail -f $LOG_DIR/$LOG_FILE'" >> ~/.bashrc
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
else
  rsync -av $SRC_DIR/keys.txt $SSH_KEYS
fi
chmod 600 $SSH_KEYS

for d in $CONKY_CONF_DIR $BIN_DIR $LOG_DIR $HOME_DIR
do
  echo $d
  sudo mkdir -p $d
  sudo chown -R $USER $d
done

chmod 700 $HOME_DIR
chmod 700 $LOG_DIR

if [ -s "$SSH_KEYS" ]
then
  echo "Ключи SSH на месте, запрещаем пользователям $USER и root вход по паролю"
  sudo passwd -d $USER
  sudo passwd -d root
  sudo sed -i -E -e 's/PermitRootLogin\s+yes/PermitRootLogin no/' /etc/ssh/sshd_config
  sudo systemctl reload ssh
fi

# Install and configure postfix and mutt for email notifications
if [ "$ENABLE_EMAIL" = "1" ] && ! command -v postfix &> /dev/null; then
    echo "Installing postfix and dependencies..."
    # Pre-configure postfix to avoid interactive prompts
    sudo debconf-set-selections <<< "postfix postfix/mailname string $(hostname)"
    sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Satellite system'"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y postfix libsasl2-modules
    
    # Configure postfix for satellite mode with Yandex SMTP
    sudo postconf -e "relayhost = [smtp.yandex.ru]:587"
    sudo postconf -e "smtp_sasl_auth_enable = yes"
    sudo postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
    sudo postconf -e "smtp_sasl_security_options = noanonymous"
    sudo postconf -e "smtp_tls_security_level = encrypt"
    sudo postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
    sudo postconf -e "smtp_use_tls = yes"
    
    # Create password file for Yandex authentication
    echo "[smtp.yandex.ru]:587    $REPORTS_EMAIL:$REPORTS_APP_PASSWD" | sudo tee /etc/postfix/sasl_passwd > /dev/null
    sudo chmod 600 /etc/postfix/sasl_passwd
    sudo postmap /etc/postfix/sasl_passwd
    
    # Restart postfix to apply changes
    sudo systemctl restart postfix
fi

if [ "$ENABLE_EMAIL" = "1" ] && ! command -v mutt &> /dev/null; then
    echo "Installing mutt..."
    sudo apt-get update -qq
    sudo apt-get install -qq -y mutt
fi

# Configure mutt if not already configured
if [ "$ENABLE_EMAIL" = "1" ] && [ ! -f "$HOME_DIR/.muttrc" ]; then
    cat > "$HOME_DIR/.muttrc" << EOL
set sendmail="/usr/sbin/sendmail -oem -oi"
set use_from=yes
set realname="Frame Reporter"
set from="$REPORTS_EMAIL"
set envelope_from=yes
set ssl_starttls=yes
set ssl_force_tls=yes
set edit_headers=yes
set charset="utf-8"
set send_charset="utf-8"
EOL
    chmod 600 "$HOME/.muttrc"
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
  sudo systemctl reload ssh
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
  sudo chmod 775 "$DEMO_DIR"
  notify-send -t 10000 "Скачиваем альбом демо-фотографий"
  $SRC_DIR/$YANDEX_DISK_DOWNLOAD_SCRIPT "$YANDEX_DISK_PUBLIC_URL" "$DEMO_ZIP" "$TMP_DEMO_ZIP"
  if [ -s "$TMP_DEMO_ZIP" ]
  then
    unzip -d "$DEMO_DIR" $TMP_DEMO_ZIP
    rm -f $TMP_DEMO_ZIP
    sudo chmod -R g+rw "$DEMO_DIR"
    sudo chown -R $USER:$MEDIA_USER "$DEMO_DIR"
  else
    rmdir "$DEMO_DIR"
  fi
fi

#if [ ! -d "$PHOTO_DIR" ]
#then
sudo mkdir -p "$PHOTO_DIR"
sudo chown -R $MEDIA_USER:$MEDIA_USER "$PHOTO_DIR"
sudo chmod 775 "$PHOTO_DIR"
#fi

if [ $SRC_DIR != $BIN_DIR ];
then
  notify-send -t 10000 "Устанавливаю версию $VERSION"
  rsync -av $SRC_DIR/$MAIN_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$INFO_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$PLACE_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$GEO_SCRIPT $BIN_DIR
  rsync -av $SRC_DIR/$TM_SCRIPT $BIN_DIR
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
sudo rsync -az --itemize-changes $SRC_DIR/$CONKY_FONT $SYSTEM_FONT_DIR | grep -q "^[>+<*dh]" && sudo fc-cache -f -v

if [ "x$RESIZE_ROOTFS" == "xyes" ]
then
  echo "Requested resize rootfs on boot, installing tools and updating the image"
  sudo rsync -av $SRC_DIR/$INITRAMFS_RESIZE_SCRIPT $INITRAMFS_SCRIPTS_DIR
  sudo rsync -av $SRC_DIR/$INITRAMFS_TOOLS_SCRIPT $INITRAMFS_HOOKS_DIR
  sudo update-initramfs -u
  echo "Initramfs resize script has been installed"
else
  if [ -s $INITRAMFS_SCRIPTS_DIR/$INITRAMFS_RESIZE_SCRIPT ]
  then
    echo "Removing resizef tools from the image"
    sudo rm -f $INITRAMFS_SCRIPTS_DIR/$INITRAMFS_RESIZE_SCRIPT
    sudo rm -f $INITRAMFS_HOOKS_DIR/$INITRAMFS_TOOLS_SCRIPT
    sudo update-initramfs -u
    echo "Initramfs resize script has been removed"
  else
    echo "Initramfs resize script is not installed"
  fi
fi

##################################################################
#Обновление логотипа

remote_logo_file='watermark.png'

target_logo_file='/usr/share/plymouth/themes/orangepi/watermark.png'
if [ -s "$target_logo_file" ]
then
  target_logo_md5=$(md5sum "$target_logo_file" | cut -d ' ' -f 1)
else
  target_logo_md5=''
fi

local_logo_file="$HOME/watermark.png"
$BIN_DIR/$YANDEX_DISK_DOWNLOAD_SCRIPT "$YANDEX_DISK_PUBLIC_URL" "$remote_logo_file" "$local_logo_file"
if [ -s "$local_logo_file" ]
then
  local_logo_md5=$(md5sum "$local_logo_file" | cut -d ' ' -f 1)
  echo "Local MD5: $local_logo_md5 Target MD5: $target_logo_md5"
  if [ "X$local_logo_md5" != "X$target_logo_md5" ]
  then
    echo "Обновляем логотип"
    notify-send -t 10000 "Обновляем логотип"
    sudo cp -f "$local_logo_file" "$target_logo_file"
    sudo update-initramfs -u
  else
    echo "Логотип актуальный, обновление не требуется"
  fi
else
  echo "Не удалось скачать логотип"
fi

remote_blackbg_file='blackbg.png'
local_blackbg_file="$HOME/blackbg.png"

$BIN_DIR/$YANDEX_DISK_DOWNLOAD_SCRIPT "$YANDEX_DISK_PUBLIC_URL" "$remote_blackbg_file" "$local_blackbg_file"

if [ -s "$local_blackbg_file" ]
then
  $BIN_DIR/$WALLPAPER_SCRIPT "$local_blackbg_file" 5
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

PARTITION_DEVICE=$(findmnt -n -o SOURCE / | sed -r 's/( )+//g')
DISK_DEVICE="/dev/$(lsblk -no pkname "$PARTITION_DEVICE" | sed -r 's/( )+//g')"
UNALLOCATED=$(($(lsblk -bno SIZE $DISK_DEVICE | sort -r | head -1) - $(lsblk -bno SIZE $PARTITION_DEVICE | sort -r | head -1)))
if (( UNALLOCATED > 1000000000 ))
then
  echo "На диске $DISK_DEVICE обнаружено нераспределенное пространство."
  echo "Раздел $PARTITION_DEVICE, содержащий корневую файловую систему,"
  echo "может быть автоматически увеличен на $UNALLOCATED байт, требуется перезагрузка."
  #touch /var/run/reboot-required
fi

if [ -f /var/run/reboot-required ]; then
  echo 'Через 10 секунд перезагружаюсь'
  notify-send -t 10000 'Через 10 секунд перезагружаюсь'
  sleep 10
  sudo reboot
fi

changed_files=$(find "$BIN_DIR" -mtime -1 -type f | grep -v .git | grep -v pycache | wc -l)
if [ "$changed_files" -ne 0 ] || [ "X$OPTION" == "Xforce" ]
then
  echo "Изменено файлов: $changed_files, перезапустим сервис"
  notify-send -t 10000 "Изменено файлов: $changed_files, запланирую перезапуск сервиса"
  #pkill conky
  #pkill unclutter
  #pkill -f feh
  #$BIN_DIR/$WALLPAPER_SCRIPT "$DEMO_DIR"
  $BIN_DIR/$MAIN_SCRIPT
  rm -f "$FRAME_CONFIG_FILE.md5"
fi

#ToDo: Вынести все настроечные переменные в общий файл
