#!/bin/bash

#Проверим, чтобы не был запущен другой экземпляр скрипта
if pidof -o %PPID -x -- "$0" >/dev/null; then
  printf >&2 '%s\n' "ERROR: Скрипт $0 уже активен"
  exit 1
else
  date
fi

#Значения по-умолчанию, переопределяются значениями из файла frame.cfg в домашней папке пользователя либо в корне флэшки
WIFI_SSID=''
WIFI_PASSWORD=''
DELAY=55.0
RANDOM_ORDER=no
DEFAULT_RECENT_MINUTES_FIRST=3000
RECENT_MINUTES_FIRST=$DEFAULT_RECENT_MINUTES_FIRST
CONFIG=frame.cfg
SLIDESHOW_DISPLAY=:0
FONT_DIR=/usr/share/fonts/truetype/freefont/
FONT=FreeMono/24
GEO_MAX_LEN=60
TIMEZONE=Moscow
SCREEN_ORIENTATION=auto
SCHEDULE=00:00-CLOCK,08:00-FRAME
UPDATE=no
REBOOT=no
HIDE_PANEL=no

CLOCK_COLOR=C8320A
CLOCK_SIZE=560
CLOCK_OFFSET=40
CLOCK_VOFFSET=320

USB_DIR=/media/usb
LOCAL_DIR=/media/photo
DEMO_DIR=/media/demo
MEDIA_USER=media

BIN_DIR=$HOME/bin
LOG_DIR=/var/log/frame
YANDEX_MAIL_APP_PASSWORD=''
YANDEX_DISK_SYNC_SCRIPT='yd.py'
CONKY_CONF=$HOME/.config/conky/conky.conf
CONKY_CONF_TEMPLATE=$HOME/.config/conky/conky.conf.template

YANDEX_DISK_PUBLIC_URL=''

DIRS="$USB_DIR $LOCAL_DIR $HOME/photo $DEMO_DIR $HOME/demo"
IMAGES_DIR=''
USER=$(whoami)
IMAGE_EXT_RE='(img|png|jpg|jpeg|heic)'

RESTART_SLIDESHOW_AFTER=0

WIFI_DEV='wlan0'
#WIFI_MAC=$((16#$(ifconfig $WIFI_DEV 2>/dev/null | awk '/ether/ {print $2}' | cut -d ':' -f 5-6 | sed 's/://g' | tr a-z A-Z)))
#WIFI_AP_PASSWORD_FILE="$HOME/user.dat"

WIFI_SSID=''
WIFI_PASSWORD=''


function unclutter_on {
  unclutter_pid=$(pgrep unclutter)
  if [ -z "$unclutter_pid" ]; then
    echo "Запускаем unclutter"
    unclutter -root >/dev/null 2>&1 &
  fi
}

function set_panel {
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus
  opacity=$(xfconf-query -c xfce4-panel -p /panels/panel-1/leave-opacity)

  if [ "X$1" == "Xoff" ] && [ "$opacity" -eq "100" ]
  then
    echo "Панель делаем невидимой"
    xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 2
    xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/leave-opacity -s 0
    xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/enter-opacity -s 0
    #xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-rgba -s 0
    xfconf-query --create -t int  -c xfce4-desktop -p /desktop-icons/style -s 0
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -s false
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable -s false
  elif [ "X$1" != "Xoff" ] && [ "$opacity" -ne "100" ]
  then
    echo "Панель делаем видимой"
    xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 0
    xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/leave-opacity -s 100
    xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/enter-opacity -s 100
    ##xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-rgba -s 0
    xfconf-query --create -t int  -c xfce4-desktop -p /desktop-icons/style -s 2
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -s true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable -s true
  fi
  xfconf-query --create -t uint -c xfce4-panel -p /panels/panel-1/background-style -s 2
}

function set_power_mode {
  if [ "X$1" == "Xon" ]
  then
    echo "Включаем дисплей"
    xset dpms force on
    xset -dpms
  else
    echo "Выключаем дисплей"
    xset dpms force off
  fi
  xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -s 0
  xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-sleep -s 0
  xfconf-query --create -t uint -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -s 0
}

function internet { wget -q --spider http://google.com 2>/dev/null && chronyc tracking | grep -i status | grep -i normal | wc -l; }

NET_DOWN=3
NET_NOT_CONNECTED=2
NET_REMOTE_FAIL=1
NET_OK=0


function get_connection_status {
  wifi_net_cnt=$(sudo nmcli d wifi list | grep -v BSSID | grep -v SIGNAL| wc -l)
  if [ "$wifi_net_cnt" -eq '0' ]
  then
    #no wifi network at all
    echo $NET_DOWN
    return
  fi

  wifi_connected=$(sudo nmcli d | grep -i wifi | grep -v -i loopback | grep -c -i -E -e '\sconnected\s')
  gw=$(ip route | awk '/default/ {print $3; exit}')
  gw_available=0
  if [ "$wifi_connected" -gt "0" ] && [ -n "$gw" ]
  then
    gw_ping_lost=$(ping -i 0.002 -c 100 -w 10 -W 10.0 $gw | grep -i loss | cut -d ',' -f 3 | sed -E 's/^\s*([0-9\.]+)\%.*/\1/' | sed -E 's/\.[0-9]+//')
    if [ -n "$gw_ping_lost" ] && [ "$gw_ping_lost" -lt "10" ]
    then
      gw_available=1
    fi
  fi

  if [ "$gw_available" -eq "0" ]
  then
    #Not connected, worth trying to connect
    echo $NET_NOT_CONNECTED
    return
  fi

  #web_available=$(wget --spider --timeout=3 --tries=3 -q https://ya.ru 2>/dev/null && echo 1)
  ntp_available=$(chronyc tracking | grep -i status | grep -i normal | wc -l)

  web_available=0
  while read -r site
  do
    if [ -n "$site" ]
    then
      site_available=$(wget --spider --timeout=5 --tries=3 -q $site 2>/dev/null && echo 1)
      if [ "X$site_available" == "X1" ]
      then
        web_available=1
        break
      fi
    fi
  done <<< $(shuf -n 5 << EOF
https://ya.ru
https://gmail.com
https://mail.ru
https://youtube.com
https://yahoo.com
https://dzen.ru
https://t.me
https://hh.ru
https://market.yandex.ru
https://kinopoisk.ru
https://rutube.ru
https://ok.ru
https://whatsapp.com
https://rambler.ru
https://pikabu.ru
https://lenta.ru
https://aliexpress.ru
https://tbank.ru
https://news.mail.ru
https://ria.ru
https://dns-shop.ru
https://drive2.ru
https://mts.ru
EOF
)

  if [ "X$web_available" != "X1" ] || [ "X$ntp_available" == "X0" ]
  then
    #External resources not available
    echo $NET_REMOTE_FAIL
  else
    #Everytyhing's fine
    echo $NET_OK
  fi
}

##################### Mount USB ####################

if [ ! -d "$LOG_DIR" ]
then
  echo "Папка для логов $LOG_DIR не существует, создаю"
  sudo mkdir -p $LOG_DIR
  sudo chown -R $USER $LOG_DIR
fi

sudo mkdir -p $USB_DIR

test_file='asDF4)SF4mADf.dat'

sudo touch $USB_DIR/$test_file || sudo umount $USB_DIR
sudo rm -f $USB_DIR/$test_file

for name in $(find /dev -name 'sd*1')
do
  n=$(mount | grep $name | wc -l)
  if [ $n -eq 0 ]
  then
    echo "Найден внешний раздел $name"
    sudo chown $USER:$USER $USB_DIR
    sudo chmod 777 $USB_DIR
    if sudo mount "$name" $USB_DIR -o umask=000,user,utf8
    then
      echo "Флэшка успешно подключена"
    fi
    pkill feh
  fi
done

USB_READY=$(mount | grep -c $USB_DIR)
if [ "$USB_READY" -gt "0" ] && [ ! -w "$USB_DIR" ]
then
  echo "Флэшка видна среди смонтированных, но записать не удается. Считаем, что флэшки нет"
  USB_READY=0
fi

########### Loading external config ##################
SECURE_TMP_DIR=$(mktemp -d /tmp/frame_config.XXXXXX)
if [ ! -d "$SECURE_TMP_DIR" ]; then
    echo "ERROR: Could not create secure temporary directory" >&2
    exit 1
fi
chmod 700 "$SECURE_TMP_DIR"

TMP_CONFIG="$SECURE_TMP_DIR/frame.cfg"
touch "$TMP_CONFIG"
chmod 600 "$TMP_CONFIG"

process_config_file() {
    local config_file="$1"
    local config_source="$2"
    
    ## Check file permissions (should not be world-writable)
    #if [ -w "$config_file" -a ! -O "$config_file" ]; then
    #    echo "WARNING: Config file $config_file is writable by others, skipping" >&2
    #    return 1
    #fi
    
    # Clear temporary config before processing
    > "$TMP_CONFIG"
    
    # Process each line with strict validation
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments and lines ending with =
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ =$ ]] && continue
        
        # Strict pattern matching for variable assignments
        if [[ "$line" =~ ^[A-Z0-9_]+=([[:print:]]+)$ ]]; then
            # Additional validation of the value
            local var_name="${line%%=*}"
            local var_value="${line#*=}"
            
            # Remove any potentially dangerous characters
            var_value="${var_value//[$'\n\r']/}"
            
            # Log accepted entries
            #echo "$(date '+%Y-%m-%d %H:%M:%S') [$config_source] Accepting: $var_name" >&2
            
            echo "$var_name=$var_value" >> "$TMP_CONFIG"
        else
            # Log rejected entries
            echo "$(date '+%Y-%m-%d %H:%M:%S') [$config_source] Rejecting invalid line: $line" >&2
        fi
    done < "$config_file"
    
    # Source the file only if it's non-empty and properly formatted
    if [ -s "$TMP_CONFIG" ]; then
        # Double-check the temporary file format
        if grep -q -v '^[A-Z0-9_]\+=[[:print:]]\+$' "$TMP_CONFIG"; then
            echo "ERROR: Malformed temporary config file, skipping" >&2
            return 1
        fi
        source "$TMP_CONFIG"
    fi
}

[ -s "$HOME/$CONFIG" ] && process_config_file "$HOME/$CONFIG" "HOME"
[ -s "$LOCAL_DIR/$CONFIG" ] && process_config_file "$LOCAL_DIR/$CONFIG" "LOCAL"
[ -s "$USB_DIR/$CONFIG" ] && process_config_file "$USB_DIR/$CONFIG" "USB"

rm -rf "$SECURE_TMP_DIR"

##################################################################################################
# Loading wifi connection details if any

if [ "$USB_READY" -gt "0" ]
then
  while IFS= read -r -d '' file
  do
    echo "Обнаружен файл с данными для подключения к сети WiFi: $file"
    WIFI_SSID2=""
    WIFI_PASSWORD2=""
    while IFS= read -r line
    do
      if [ "X$WIFI_SSID2" == 'X' ]; then
        WIFI_SSID2=$line
      else
        if [ "X$WIFI_PASSWORD2" == 'X' ]; then
          WIFI_PASSWORD2=$line
          if [ "X$WIFI_SSID2" != "X$WIFI_SSID" ] || [ "X$WIFI_PASSWORD2" != "X$WIFI_PASSWORD" ]
          then
            wifi_net_cnt=$(sudo nmcli --fields SSID d wifi| grep -c "$WIFI_SSID2")
            if [ "$wifi_net_cnt" -gt "0" ]
            then
              echo "Подключаемся к сети $WIFI_SSID2"
              sudo nmcli device wifi connect "$WIFI_SSID2" password "$WIFI_PASSWORD2" ifname $WIFI_DEV
              connection_status=$(internet)
              echo "Статус подключения: $connection_status"
              ESCAPED_WIFI_SSID2=$(printf '%s\n' "$WIFI_SSID2" | sed 's/[.[\()*?^$+{}|\\]/\\&/g')
              connected=$(sudo nmcli --fields IN-USE,SSID d wifi | grep -c -E -e "^\*\s+$ESCAPED_WIFI_SSID2")
              if [ "$connected" -gt "0" ]
              then
                echo "Успешно подключились к сети $WIFI_SSID2"
                WIFI_SSID=$WIFI_SSID2
                WIFI_PASSWORD=$WIFI_PASSWORD2
              else
                echo "Не удалось подключиться к сети $WIFI_SSID2"
                sudo nmcli con del "$WIFI_SSID2"
              fi
              sudo mv -f "$file" "$file.backup"
            else
              echo "Сеть $WIFI_SSID2 не нашлась в списке подключений"
            fi
          else
            echo "Параметры сети в файле $file совпадают с уже известными"
          fi
        fi
      fi
    done < <(cat $file | dos2unix | grep -v -e "^$" | head -2)
  done <  <(find $USB_DIR -type f -size -256 -regextype egrep -iregex '.*/wifi.*\.(cfg|txt)' -print0)
fi

##########################################################################################################
#Проверка статуса подключения, многоуровневая логика восстановления подключения

#Определим целевой статус, требуется ли подключение к существующей сети
if [ "X$WIFI_SSID" != "X" ] && [ "X$WIFI_PASSWORD" != "X" ]
then
  st=$(get_connection_status)
  if [ "$st" -eq "$NET_DOWN" ]
  then

    echo "Не найдено ни одной сети WiFi. Перегружаем Network Manager, после чего обновим статус подключения"

    echo "Состояние до перезагрузки:"
    ifconfig $WIFI_DEV
    sudo nmcli d
    sudo nmcli d wifi
    sudo nmcli c
    sudo rfkill

    sudo systemctl stop NetworkManager
    sudo systemctl stop wpa_supplicant
    sudo ifconfig $WIFI_DEV down
    sudo ip link set $WIFI_DEV down
    sudo rfkill block wlan

    sleep 5
    sudo rfkill unblock wlan
    sudo ip link set $WIFI_DEV up
    sudo ifconfig $WIFI_DEV up
    sudo systemctl start wpa_supplicant
    sudo systemctl start NetworkManager
    sleep 10

    echo "Состояние после перезагрузки:"
    ifconfig $WIFI_DEV
    sudo nmcli d
    sudo nmcli d wifi
    sudo nmcli c
    sudo rfkill

    st=$(get_connection_status)
  fi

  case "$st" in
    $NET_DOWN)
      echo "Сеть восстановить перезапуском Network Manager не удалось, возможно, потребуется перезагрузка"
      ;;
    $NET_NOT_CONNECTED)
      echo "Сеть не подключена, пытаемся подключиться"
      pkill nm-applet
      for ssid in $(sudo nmcli con  | grep -i wlan0 | cut -d ' ' -f 1); do sudo nmcli con del $ssid; done
      res=$(sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" ifname $WIFI_DEV 2>&1)
      echo "Res: $res"
      if [[ $res == *"property is invalid"* ]] || [[ $res == *"not provided"* ]]
      then
        echo "Неправильный пароль $WIFI_PASSWORD"
      else
        st=$(get_connection_status)
        echo "Состояние после подключения: $st"
      fi
      ;;
    $NET_REMOTE_FAIL)
      echo "Сеть подключена, но доступен только шлюз по-умолчанию. Вероятно, проблема у провайдера"
      ;;
    $NET_OK)
      echo "Сеть подключена, внешние ресурсы доступны"
      ;;
    *)
      echo "Неизвестный статус сети: $st"
      ;;
  esac
fi

if ! [[ $RECENT_MINUTES_FIRST =~ ^[0-9]+$ ]] ; then
  echo "Нечисловое значение в параметре RECENT_MINUTES_FIRST: $RECENT_MINUTES_FIRST, меняем на $DEFAULT_RECENT_MINUTES_FIRST"
  RECENT_MINUTES_FIRST=$DEFAULT_RECENT_MINUTES_FIRST
fi


read -r -d '' config << EOM
################################
#Frame configuration
################################

VERSION=_VERSION_

#Разовое автоматическое обновление, для разрешения выставить в yes. После применения автоматически сбрасывается в no
UPDATE=no

#Разовый автоматический перезапуск рамки, для разрешения выставить в yes. После применения автоматически сбрасывается в no
REBOOT=no

#Разовая отсылка логов разработчику, для разрешения выставить в yes. После применения автоматически сбрасывается в no
#Функциональность работает только при указании пароля приложения Yandex Mail в переменной YANDEX_MAIL_APP_PASSWORD
SEND_LOGS=no

#Интервал между фотографиями в слайдшоу, в секундах
DELAY=$DELAY

#Интервал до перезапуска слайдшоу в минутах, полезно для переключения на другой день в истории
#при значении 0 слайдшоу не перезапускается
RESTART_SLIDESHOW_AFTER=$RESTART_SLIDESHOW_AFTER

#Порядок смены слайдов. yes - случайный, no - сортировка по имени файла, но со случайным начальным файлом
RANDOM_ORDER=$RANDOM_ORDER

#Начинать слайдшоу с фотографий, загруженных за последние Х минут
RECENT_MINUTES_FIRST=$RECENT_MINUTES_FIRST

#Актуально только для многомониторных инсталляций, по-умолчанию значение :0
SLIDESHOW_DISPLAY=$SLIDESHOW_DISPLAY

#Настройки вывода информации о текущем слайде - время съемки и описание гео-точки 
#Путь к папке со шрифтами
FONT_DIR=$FONT_DIR
#Название и размер шрифта
FONT=$FONT
#Максимальная длина описания гео-точки в символах
GEO_MAX_LEN=$GEO_MAX_LEN

#Таймзона - можно указать название города (Kaliningrad,Moscow) или часовой пояс (GMT+3)
TIMEZONE=$TIMEZONE

#Ориентация экрана - normal (соответствует аппаратному положению матрицы), 
#left, right, inverted, auto (автоматическое определение положения матрицы)
SCREEN_ORIENTATION=$SCREEN_ORIENTATION

#Конфигурация часов
CLOCK_COLOR=$CLOCK_COLOR
CLOCK_SIZE=$CLOCK_SIZE
CLOCK_OFFSET=$CLOCK_OFFSET
CLOCK_VOFFSET=$CLOCK_VOFFSET

#Опция HIDE_PANEL=yes позволяет скрыть панель с элементами управления и меню с программами
#При этом сама панель не удаляется, но делается прозрачной, поэтому для открытия меню
#достаточно кликнуть в левом верхнем углу экрана
HIDE_PANEL=$HIDE_PANEL

#Расписание задается как множество пар время-режим через запятую
#время в формате 23:59, режим - FRAME (слайдшоу), CLOCK (часы), DESKTOP (рабочий стол) или OFF (выключенный экран)
#Например,
#SCHEDULE=23:00-OFF,5:00-CLOCK,8:00-FRAME,22:00-CLOCK
SCHEDULE=$SCHEDULE

#Параметры подключения к сети WiFi
WIFI_SSID="$WIFI_SSID"
WIFI_PASSWORD="$WIFI_PASSWORD"

#Пароль приложения Yandex Mail для отправки логов
#Сформировать пароль можно в интерфейсе настроек аккаунта Yandex по ссылке
#https://id.yandex.ru/security/app-passwords
YANDEX_MAIL_APP_PASSWORD="$YANDEX_MAIL_APP_PASSWORD"

#URL к публично-доступной папке на Яндекс-Диске. Если ссылка задана и активна, содержимое данной папки Я.Диска
#будет регулярно синхронизироваться в локальную папку с фотографиями
#Параметр должен выглядеть так:
#YANDEX_DISK_PUBLIC_URL=https://disk.yandex.ru/d/yg2o_OtadJovFw
#В качестве примера использована ссылка на существующую папку на Яндекс.Диске,
#содержащую подборку красивых фотографий природы
YANDEX_DISK_PUBLIC_URL="$YANDEX_DISK_PUBLIC_URL"

EOM

config_changed=0
if [ -s "$HOME/$CONFIG.md5" ]
then
  c1=$(echo "$config"| md5sum | awk '{print $1}')
  c2=$(cat $HOME/$CONFIG.md5)
  if [ "$c1" != "$c2" ]
  then
    config_changed=1
  fi
else
  config_changed=1
fi

if [ "$config_changed" -gt "0" ]
then
  echo "Обнаружено изменение конфига"
  pkill -f feh
  pkill conky
  sleep 3

  echo "$config" > "$HOME/$CONFIG"
  echo "$c1" > "$HOME/$CONFIG.md5"

  sudo rsync -aq $HOME/$CONFIG $LOCAL_DIR/$CONFIG
  sudo chown $MEDIA_USER:$MEDIA_USER $LOCAL_DIR/$CONFIG

  cat "$CONKY_CONF_TEMPLATE" | \
  sed "s/_CLOCK_COLOR_/$CLOCK_COLOR/" |\
  sed "s/_CLOCK_SIZE_/$CLOCK_SIZE/" |\
  sed "s/_CLOCK_OFFSET_/$CLOCK_OFFSET/" |\
  sed "s/_CLOCK_VOFFSET_/$CLOCK_VOFFSET/" > "$CONKY_CONF"
fi


if [ "$USB_READY" -gt "0" ]
then
  diff=$(diff $HOME/$CONFIG $USB_DIR/$CONFIG 2>&1)
  if [ -n "$diff" ]
  then
    echo "Copy $HOME/$CONFIG to $USB_DIR/$CONFIG"
    cat "$HOME/$CONFIG" > "$USB_DIR/$CONFIG"
  fi
  diff2=$(diff $HOME/history.txt $USB_DIR/history.txt 2>&1)
  if [ -n "$diff2" ]
  then
    cp -f $BIN_DIR/history* $USB_DIR
    rm -f $USB_DIR/changes*.txt
  fi
fi

if [ "X$REBOOT" == "Xyes" ]
then
  echo "В конфиге выставлен флаг перезагрузки, выполняем"
  sudo reboot
fi

export DISPLAY=$SLIDESHOW_DISPLAY

############################################################################################

# 1. Check if SCREEN_ORIENTATION is valid (non-fatal)
valid_orientation=false
case "$SCREEN_ORIENTATION" in
  normal|left|right|inverted|auto)
    valid_orientation=true
    ;;
esac

# 2. Get current orientation (only if SCREEN_ORIENTATION is valid)
if [[ "$valid_orientation" == true ]]; then
  current_orientation=$(xrandr | grep " connected" | sed -E 's/^.* (normal|left|right|inverted)\s+\(.*$/\1/')

  case "$current_orientation" in
    normal|left|right|inverted)
    ;;
    *)
      current_orientation='normal'
  esac

  if [ "$SCREEN_ORIENTATION" == "auto" ]; then
    # Auto-detect orientation based on screen size

    size=$(xrandr | grep '*' | awk '{print $1}')

    # Extract dimensions using regular expression
    if [[ "$size" =~ ([0-9]+)x([0-9]+)$ ]]; then
      width="${BASH_REMATCH[1]}"
      height="${BASH_REMATCH[2]}"

      # Compare dimensions
      if (( width < height )); then
        SCREEN_ORIENTATION="right"
      else
        SCREEN_ORIENTATION="normal"
      fi
    else
      echo "String does not match expected format."
    fi
  fi

  # 3. Compare and apply if needed (only if SCREEN_ORIENTATION is valid)
  if [[ "$current_orientation" != "$SCREEN_ORIENTATION" ]]; then
    echo "Changing orientation from '$current_orientation' to '$SCREEN_ORIENTATION'..."
    xrandr -o "$SCREEN_ORIENTATION"
    if [[ $? -eq 0 ]]; then
      echo "Orientation set successfully."
    else
      echo "Error setting orientation."
    fi
  fi
else
  echo "Warning: Invalid SCREEN_ORIENTATION: '$SCREEN_ORIENTATION'. Skipping orientation change."
fi

############################################################################################

shopt -s extglob
#TIME=$(date +%H%M | sed 's/^0\{1,3\}//')

NTP=$(chronyc tracking | grep -i status | grep -i normal | wc -l)

if [ "$NTP" -eq "0" ]
then
  echo "Синхронизация с NTP не работает, включаем принудительный дневной режим"
  target_mode=FRAME
else

  if [ "X$UPDATE" == "Xyes" ]
  then
    echo "Запрошено автоматическое обновление"
    nohup sh -c 'cd $HOME/frame && sleep 3 && git pull && ./update.sh' >> $LOG_DIR/update.log 2>&1 &
    echo "Управление передается скрипту обновления, скрипт $0 завершается"
    exit
  fi

  TZFILE_NEW=$(find /usr/share/zoneinfo -type f | grep -i "$TIMEZONE" | sort | head -1)
  TZFILE_CUR=$(readlink /etc/localtime)
  if [ -s "$TZFILE_NEW" ] && [ "X$TZFILE_NEW" != "X$TZFILE_CUR" ]
  then
    echo "Часовой пояс: $TIMEZONE, меняем $TZFILE_CUR на $TZFILE_NEW"
    sudo ln -f -s $TZFILE_NEW /etc/localtime
    date
  fi


  #############  Определение текущего режима ################################################

  sorted=$(for interval in $(echo "$SCHEDULE" | sed 's/,/ /g'); do
    IFS='-' read -r hm mode <<< "$interval"
    seconds=$(( 1000000 + $(date -d "$hm" +%s) - $(date -d "00:00" +%s) ))
    echo "$seconds-$mode-$hm"
  done | sort -r)

  if [ "X$TEST_HM" != "X" ]
  then
    now=$(( 1000000 + $(date -d "$TEST_HM" +%s) - $(date -d "00:00" +%s) ))
  else
    now=$(( 1000000 + $(date +%s) - $(date -d "00:00" +%s) ))
  fi

  target_mode=""

  for time_mode in $sorted; do
    IFS='-' read -r time mode hm <<< "$time_mode"
    #echo "now='$now' time='$time' mode='$mode' hm='$hm'"
    if [ "X$target_mode" == "X" ]
    then
      target_mode=$mode
    fi
    if [ "$time" -le "$now" ]
    then
      target_mode=$mode
      break
    fi
  done

  if [ "X$target_mode" == "X" ]
  then
    target_mode='FRAME'
  fi

fi

if [ "X$HIDE_PANEL" == "Xyes" ]
then
  set_panel off
else
  set_panel on
fi

pkill -f xfce4-display-settings

case "$target_mode" in
FRAME)
  pkill conky

  PID=$(pgrep exiftran)
  if [ -n "$PID" ]
  then
    echo "Exiftran уже работает, выхожу"
    exit 0
  fi

  PID=$(pgrep feh)
  if [ -z "$PID" ]
  then
    echo "Переход в режим рамки"
    unclutter_on
    set_power_mode on
    #xset dpms force on
    #xset -dpms

    for d in $DIRS
    do
      if [ -d "$d" ]
      then
        TMP_ALL_LIST="/tmp/all.lst"
        find "$d" -type f -size +100k -regextype egrep -iregex ".*\.$IMAGE_EXT_RE" | sort  > $TMP_ALL_LIST
        if [ -s "$TMP_ALL_LIST" ]
        then
          IMAGES_DIR=$d
          echo "Каталог с фото: $IMAGES_DIR"
          TMP_IMAGES_DIR="/tmp/frame/$IMAGES_DIR"
          mkdir -p "$TMP_IMAGES_DIR"
          ALL_LIST="$TMP_IMAGES_DIR/all.lst"
          cat "$TMP_ALL_LIST" > "$ALL_LIST"
          PLAY_LIST="$TMP_IMAGES_DIR/play.lst"

          RECENT_LIST="$TMP_IMAGES_DIR/recent.lst"
          OLDER_LIST="$TMP_IMAGES_DIR/older.lst"

          unlink "$RECENT_LIST" 2>/dev/null
          unlink "$OLDER_LIST" 2>/dev/null

          find "$d" -type f -size +100k -regextype egrep -iregex ".*\.$IMAGE_EXT_RE" -mmin -$RECENT_MINUTES_FIRST | grep -v '/\.' | grep -v -i 'trash' | sort > "$RECENT_LIST"
          find "$d" -type f -size +100k -regextype egrep -iregex ".*\.$IMAGE_EXT_RE" -mmin +$RECENT_MINUTES_FIRST | grep -v '/\.' | grep -v -i 'trash' | sort > "$OLDER_LIST"

          unlink "$PLAY_LIST" 2>/dev/null

          if [ -s "$RECENT_LIST" ]
          then
            if [ "X$RANDOM_ORDER" == "Xyes" ]
            then
              echo "Добавляем в плейлист новые фотографии в случайном порядке"
              cat "$RECENT_LIST" | shuf >> "$PLAY_LIST"
            else
              lines=$(wc -l "$RECENT_LIST" | cut -d ' ' -f 1)
              offset=$(echo "1 + $RANDOM % $lines" | bc)
              tail=$(echo "$lines*2 - $offset + 1" | bc)
              echo "Добавляем в плейлист $lines новых фотографий, начиная c $offset"
              cat "$RECENT_LIST" "$RECENT_LIST" | tail -n $tail | head -n $lines >> "$PLAY_LIST"
            fi
          else
            echo "Новых фотографий в $IMAGES_DIR не найдено"
          fi
          if [ -s "$OLDER_LIST" ]
          then
            if [ "X$RANDOM_ORDER" == "Xyes" ]
            then
              echo "Добавляем в плейлист старые фотографии в случайном порядке"
              cat "$OLDER_LIST" | shuf >> "$PLAY_LIST"
            else
              lines=$(wc -l "$OLDER_LIST" | cut -d ' ' -f 1)
              offset=$(echo "1 + $RANDOM % $lines" | bc)
              tail=$(echo "$lines*2 - $offset + 1" | bc)
              echo "Добавляем в плейлист $lines старых фотографий, начиная c $offset"
              cat "$OLDER_LIST" "$OLDER_LIST" | tail -n $tail | head -n $lines >> "$PLAY_LIST"
            fi
          else
            echo "Старых фотографий в $IMAGES_DIR не найдено"
          fi

          #Удалим старую версию списка
          unlink "$IMAGES_DIR/play.lst" 2>/dev/null

          break
        fi
      fi
    done

    sudo chown -R $USER:$USER "$IMAGES_DIR" 2>/dev/null

    ############ Настройка периодического задания для запуска синхронизации с Яндекс-Диском ##################
    cur_crontab_line=$(crontab -l 2>/dev/null | grep $YANDEX_DISK_SYNC_SCRIPT)
    if [ -n "$YANDEX_DISK_PUBLIC_URL" ] && [ -n "$WIFI_SSID" ]
    then
      if [ "$USB_READY" -gt "0" ]
      then
        YANDEX_DISK_DIR=$USB_DIR/yandex.disk
      else
        YANDEX_DISK_DIR=$LOCAL_DIR/yandex.disk
      fi
      target_crontab_line="3,13,23,33,43,53 * * * * python3 $BIN_DIR/$YANDEX_DISK_SYNC_SCRIPT $HOME/$CONFIG $YANDEX_DISK_DIR >> $LOG_DIR/cron.log 2>&1"
      if [ "X$target_crontab_line" != "X$cur_crontab_line" ]
      then
        echo "Включаем синхронизацию с Яндекс Диском в папку $YANDEX_DISK_DIR"
        (crontab -l 2>/dev/null | grep -v $YANDEX_DISK_SYNC_SCRIPT; echo "$target_crontab_line") | crontab -
      fi
    else
      if [ -n "$cur_crontab_line" ]
      then
        target_crontab_line=""
        echo "Выключаем синхронизацию с Яндекс Диском"
        crontab -l 2>/dev/null | grep -v $YANDEX_DISK_SYNC_SCRIPT | crontab -l
      fi
    fi

    #Удалим старую версию списка
    unlink "$IMAGES_DIR/processed.lst" 2>/dev/null

    PROCESSED_LIST="$TMP_IMAGES_DIR/processed.lst"
    touch "$PROCESSED_LIST"
    diff=$(diff "$ALL_LIST" "$PROCESSED_LIST")
    if [ -n "$diff" ]
    then
      PID=$(pgrep find)
      if [ -z "$PID" ]
      then
        cat "$ALL_LIST" > "$PROCESSED_LIST"
        echo "Обработка в фоне пользовательских POI"
        find "$IMAGES_DIR" -type f -size +100k -regextype egrep -iregex ".*[0-9]+\s*(km|m)\.$IMAGE_EXT_RE" -exec ~/bin/get_place.py '{}' \; >/dev/null 2>&1 &
        echo "Запуск в фоне автоповорота фотографий"
        find "$IMAGES_DIR" -type f -size +100k -regextype egrep -iregex ".*\.$IMAGE_EXT_RE" -exec exiftran -ai '{}' \;  >/dev/null 2>&1 &
      else
        echo "Автоповорот уже запущен, пропускаю"
      fi
    fi

#    #По-умолчанию порядок случайный
#    ORDER_OPTIONS=('-z')
#    if [ "X$RANDOM_ORDER" == "Xno" ]
#    then
#      #Если пользователь отключил случайный порядок, отсортируем файлы по имени
#      echo "Задан последовательный порядок воспроизведения, отсортируем файлы по имени"
#      ORDER_OPTIONS=('-S')
#      d=$(cat $PLAY_LIST | sed -E -e "s/^.*\///g" | grep -E -e "^[0-9]{8}\_[0-9]{6}" | cut -c 1-8 | sort -u | shuf -n 1)
#      if [ -n "$d" ]
#      then
#        #Если файлы имеют в имени дату - найдем случайный день и сдвинем начало презентации на первый файл от этого дня
#        echo "Найдем самую раннюю фотографию за дату $d:"
#        f=$(cat $PLAY_LIST | grep "$d" | sort | head -1)
#      else
#        echo "Возьмем в качестве начального случайный файл из плейлиста"
#        f=$(cat $PLAY_LIST | shuf -n 1)
#      fi
#      if [ -n "$f" ]
#      then
#        echo "Начнем слайдшоу с файла $f"
#        ORDER_OPTIONS=('-S' 'name' '--start-at' "$f")
#      fi
#    else
#      echo "Пользователь задал случайный порядок отображения: $RANDOM_ORDER"
#    fi


    PID=$(pgrep feh)
    if [ -z "$PID" ]
    then
      sleep_to_restart=$(echo "$RESTART_SLIDESHOW_AFTER*60-10" | bc)
      if [ "$sleep_to_restart" -gt 0 ]
      then
        echo "Запускаем таймер на $sleep_to_restart секунд до перезапуска слайдшоу"
        nohup sh -c "sleep $sleep_to_restart; pkill -f feh" >/dev/null 2>&1 &
      fi
      feh -V -r -Z -F -Y -D $DELAY -C $FONT_DIR -e $FONT --info "~/bin/get_info.sh %F $GEO_MAX_LEN" --draw-tinted -f $PLAY_LIST >> /var/log/frame/feh.log 2>&1 &
#      feh -V -r -Z -F -Y -D $DELAY "${ORDER_OPTIONS[@]}" -C $FONT_DIR -e $FONT --info "~/bin/get_info.sh %F $GEO_MAX_LEN" --draw-tinted -f $PLAY_LIST >> /var/log/frame/feh.log 2>&1 &
    else
      echo "Feh уже успел запуститься"
    fi
  fi
  ;;
CLOCK)
  pkill feh

#  PID=`pgrep dclock`
  PID=$(pgrep conky)
  if [ -z "$PID" ]
  then
    echo "Переход в режим часов"
    unclutter_on
    #Конфигурация часов сохранена в файле ~/.config/conky/conky.conf
    conky
#    dclock -nobell -miltime -tails -noscroll -blink -nofade -noalarm -thickness 0.12 -slope 70.0 -bd "black" -bg "black" -fg "darkorange" -led_off "black" &
    sleep 2s
  fi
  wmctrl -r conky -b add,fullscreen,above
  set_power_mode on
  ;;
DESKTOP)
  PID1=$(pgrep feh)
  PID2=$(pgrep conky)
  PID3=$(pgrep unclutter)

  if [ -n "$PID1" ] || [ -n "$PID2" ] || [ -n "$PID3" ]
  then
    echo "Переход в режим рабочего стола"
    pkill unclutter
    pkill feh
    pkill conky
    set_power_mode on
  fi
  ;;
OFF)
  set_power_mode standby
  ;;
*)
  echo "Неизвестный режим '$target_mode'"
esac
