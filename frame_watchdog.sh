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
CONFIG=frame.cfg
SLIDESHOW_DISPLAY=:0
FONT_DIR=/usr/share/fonts/truetype/freefont/
FONT=FreeMono/24
GEO_MAX_LEN=60
TIMEZONE=Moscow
SCREEN_ORIENTATION=auto
SCHEDULE=05:00-CLOCK,07:00-FRAME,22:00-CLOCK,23:30-OFF
UPDATE=no
REBOOT=no

CLOCK_COLOR=C8320A
CLOCK_SIZE=560
CLOCK_OFFSET=40
CLOCK_VOFFSET=320

USB_DIR=/media/usb
BIN_DIR=$HOME/bin
LOG_DIR=/var/log/frame
YANDEX_DISK_SYNC_SCRIPT='yd.py'
CONKY_CONF=$HOME/.config/conky/conky.conf
CONKY_CONF_TEMPLATE=$HOME/.config/conky/conky.conf.template

YANDEX_DISK_PUBLIC_URL=''

DIRS="$USB_DIR /media/photo $HOME/photo /media/demo $HOME/demo"
IMAGES_DIR=''
USER=$(whoami)

RESTART_SLIDESHOW_AFTER=120

WIFI_DEV='wlan0'
WIFI_MAC=$((16#$(ifconfig $WIFI_DEV 2>/dev/null | awk '/ether/ {print $2}' | cut -d ':' -f 5-6 | sed 's/://g' | tr a-z A-Z)))
WIFI_AP_PASSWORD_FILE="$HOME/user.dat"

WIFI_SSID=''
WIFI_PASSWORD=''

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

  web_available=$(wget --spider --timeout=3 --tries=3 -q https://ya.ru 2>/dev/null && echo 1)
  ntp_available=$(chronyc tracking | grep -i status | grep -i normal | wc -l)

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

########### Loading external config ##################
TMP_CONFIG="/tmp/frame.cfg"
if [ -s "$HOME/$CONFIG" ]
then
  grep -E -e "^[A-Z0-9_]+\=" "$HOME/$CONFIG" > $TMP_CONFIG
  source "$TMP_CONFIG"
fi

if [ -s "$USB_DIR/$CONFIG" ]
then
  grep -E -e "^[A-Z0-_]+\=" "$USB_DIR/$CONFIG" > $TMP_CONFIG
  source "$TMP_CONFIG"
fi


##################################################################################################
# Loading wifi connection details if any

while IFS= read -r -d '' file
do
  tmp_wifi_config=/tmp/wifi.cfg
  echo "Обнаружен файл с данными для подключения к сети WiFi: $file"
  cat "$file" > $tmp_wifi_config
  dos2unix $tmp_wifi_config
  WIFI_SSID2=""
  WIFI_PASSWORD2=""
  for line in $(grep -v -e '^$' $tmp_wifi_config | head -2)
  do
    if [ "X$WIFI_SSID2" == 'X' ]; then
      WIFI_SSID2=$line
    else
      if [ "X$WIFI_PASSWORD2" == 'X' ]; then
        WIFI_PASSWORD2=$line
        if [ "X$WIFI_SSID2" != "X$WIFI_SSID" ] || [ "X$WIFI_PASSWORD2" != "X$WIFI_PASSWORD" ]
        then
          WIFI_SSID=$WIFI_SSID2
          WIFI_PASSWORD=$WIFI_PASSWORD2
          echo "Подключаемся к сети $WIFI_SSID"
          sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" ifname $WIFI_DEV
          connection_status=$(internet)
          echo "Статус подключения: $connection_status"
        else
          echo "Параметры сети в файле $file совпадают с уже известными"
        fi
      fi
    fi
  done
  mv -f "$file" "$file.backup"
done <  <(find $USB_DIR -type f -size -256 -regextype egrep -iregex '.*/wifi.*\.(cfg|txt)' -print0)


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
      echo "Все отлично, внешние ресурсы доступны"
      ;;
    *)
      echo "Неизвестный статус сети: $st"
      ;;
  esac
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

#Интервал между фотографиями в слайдшоу, в секундах
DELAY=$DELAY

#Интервал до перезапуска слайдшоу в минутах, полезно для переключения на другой день в истории
RESTART_SLIDESHOW_AFTER=$RESTART_SLIDESHOW_AFTER

#Порядок смены слайдов. yes - случайный, no - сортировка по имени файла, но со случайным начальным файлом
RANDOM_ORDER=$RANDOM_ORDER

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

#Ориентация экрана - normal (соответствует аппаратному положению матрицу), left, right, auto (приведение к горизонтальному)
SCREEN_ORIENTATION=$SCREEN_ORIENTATION

#Конфигурация часов
CLOCK_COLOR=$CLOCK_COLOR
CLOCK_SIZE=$CLOCK_SIZE
CLOCK_OFFSET=$CLOCK_OFFSET
CLOCK_VOFFSET=$CLOCK_VOFFSET

#Расписание задается как множество пар время-режим через запятую
#время в формате 23:59, режим - FRAME (слайдшоу), CLOCK (часы) или OFF (выключенный экран)
#Например,
#SCHEDULE=23:00-OFF,5:00-CLOCK,8:00-FRAME,22:00-CLOCK
SCHEDULE=$SCHEDULE

#Параметры подключения к сети WiFi
WIFI_SSID=$WIFI_SSID
WIFI_PASSWORD=$WIFI_PASSWORD

#URL к публично-доступной папке на Яндекс-Диске. Если ссылка задана и активна, содержимое данной папки Я.Диска
#будет регулярно синхронизироваться в локальную папку с фотографиями
#Параметр должен выглядеть так:
#YANDEX_DISK_PUBLIC_URL=https://disk.yandex.ru/d/yg2o_OtadJovFw
#В качестве примера использована ссылка на существующую папку на Яндекс.Диске,
#содержащую подборку красивых фотографий природы
YANDEX_DISK_PUBLIC_URL=$YANDEX_DISK_PUBLIC_URL

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
  cat "$CONKY_CONF_TEMPLATE" | \
  sed "s/_CLOCK_COLOR_/$CLOCK_COLOR/" |\
  sed "s/_CLOCK_SIZE_/$CLOCK_SIZE/" |\
  sed "s/_CLOCK_OFFSET_/$CLOCK_OFFSET/" |\
  sed "s/_CLOCK_VOFFSET_/$CLOCK_VOFFSET/" > "$CONKY_CONF"

  ############ Настройка периодического задания для запуска синхронизации с Яндекс-Диском ##################
  if [ -n "$YANDEX_DISK_PUBLIC_URL" ] && [ -n "$WIFI_SSID" ]
  then
    target_crontab_line="*/5 * * * * python3 $BIN_DIR/$YANDEX_DISK_SYNC_SCRIPT $HOME/$CONFIG $IMAGES_DIR/yandex >> $LOG_DIR/cron.log 2>&1"
  else
    target_crontab_line=""
  fi
  cur_crontab_line=$(crontab -l 2>/dev/null | grep $YANDEX_DISK_SYNC_SCRIPT)

  if [ "X$target_crontab_line" != "X$cur_crontab_line" ]
  then
    if [ -n "$target_crontab_line" ]
    then
      echo "Switching on sync with Yandex Disk to folder $IMAGES_DIR/yandex"
      (crontab -l 2>/dev/null | grep -v $YANDEX_DISK_SYNC_SCRIPT; echo "$target_crontab_line") | crontab -
    else
      echo "Switching off sync with Yandex Disk"
      crontab -l 2>/dev/null | grep -v $YANDEX_DISK_SYNC_SCRIPT | crontab -l
    fi
  fi
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

unclutter_pid=$(pgrep unclutter)
if [ -z "$unclutter_pid" ]; then
  unclutter -root >/dev/null 2>&1 &
fi

############################################################################################

shopt -s extglob
TIME=$(date +%H%M | sed 's/^0\{1,3\}//')

NTP=$(chronyc tracking | grep -i status | grep -i normal | wc -l)

if (( $NTP == 0 ))
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
    date
    echo "Переход в режим рамки"
    xset dpms force on
    xset -dpms
    for d in $DIRS
    do
      if [ -d "$d" ]
      then
        TMP_PLAYLIST="/tmp/play.lst"
        find $d -size +100k | grep -i -E -e '(img|png|jpg|jpeg|heic)' > $TMP_PLAYLIST
        if [ -s "$TMP_PLAYLIST" ]
        then
          IMAGES_DIR=$d
          echo "Каталог с фото: $IMAGES_DIR"
          PLAYLIST="$IMAGES_DIR/play.lst"
          cat $TMP_PLAYLIST > $PLAYLIST
          break
        fi
      fi
    done

    sudo chown -R $USER:$USER $IMAGES_DIR 2>/dev/null

    ROTATELIST="$IMAGES_DIR/processed.lst"
    touch $ROTATELIST
    diff=$(diff $PLAYLIST $ROTATELIST)
    if [ ! -z "$diff" ]
    then
      PID=$(pgrep find)
      if [ -z "$PID" ]
      then
        cat $PLAYLIST > $ROTATELIST
        echo "Обработка в фоне пользовательских POI"
        find $IMAGES_DIR -regextype egrep -iregex '.*[0-9]+\s*(km|m)\.(img|png|jpg|jpeg|heic)' -exec ~/bin/get_place.py '{}' \; >/dev/null 2>&1 &
        echo "Запуск в фоне автоповорота фотографий"
        find $IMAGES_DIR -type f -not -empty -exec exiftran -ai '{}' \;  >/dev/null 2>&1 &
      else
        echo "Автоповорот уже запущен, пропускаю"
      fi
    fi

    #По-умолчанию порядок случайный
    ORDER_OPTIONS=('-z')
    if [ "X$RANDOM_ORDER" == "Xno" ]
    then
      #Если пользователь отключил случайный порядок, отсортируем файлы по имени
      echo "Задан последовательный порядок воспроизведения, отсортируем файлы по имени"
      ORDER_OPTIONS=('-S')
      d=$(cat $PLAYLIST | sed -E -e "s/^.*\///g" | grep -E -e "^[0-9]{8}\_[0-9]{6}" | cut -c 1-8 | sort -u | shuf -n 1)
      if [ -n "$d" ]
      then
        #Если файлы имеют в имени дату - найдем случайный день и сдвинем начало презентации на первый файл от этого дня
        echo "Найдем самую раннюю фотографию за дату $d:"
        f=$(cat $PLAYLIST | grep "$d" | sort | head -1)
      else
        echo "Возьмем в качестве начального случайный файл из плейлиста"
        f=$(cat $PLAYLIST | shuf -n 1)
      fi
      if [ -n "$f" ]
      then
        echo "Начнем слайдшоу с файла $f"
        ORDER_OPTIONS=('-S' 'name' '--start-at' "$f")
      fi
  else
      echo "Пользователь задал случайный порядок отображения: $RANDOM_ORDER"
    fi
    set -x
    PID=$(pgrep feh)
    if [ -z "$PID" ]
    then
      sleep_to_restart=$(echo "$RESTART_SLIDESHOW_AFTER*60-10" | bc)
      if [ "$sleep_to_restart" -gt 0 ]
      then
        echo "Запускаем таймер на $sleep_to_restart секунд до перезапуска слайдшоу"
        nohup sh -c "sleep $sleep_to_restart; pkill -f feh" >/dev/null 2>&1 &
      fi
      feh -V -r -Z -F -Y -D $DELAY "${ORDER_OPTIONS[@]}" -C $FONT_DIR -e $FONT --info "~/bin/get_info.sh %F $GEO_MAX_LEN" --draw-tinted -f $PLAYLIST >> /var/log/frame/feh.log 2>&1 &
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
    date
    echo "Переход в режим часов"
    #Конфигурация часов сохранена в файле ~/.config/conky/conky.conf
    conky
#    dclock -nobell -miltime -tails -noscroll -blink -nofade -noalarm -thickness 0.12 -slope 70.0 -bd "black" -bg "black" -fg "darkorange" -led_off "black" &
    sleep 2s
  fi
  wmctrl -r conky -b add,fullscreen,above
  xset dpms force on
  xset -dpms
  ;;
OFF)
  xset dpms force off
  ;;
*)
  echo "Неизвестный режим '$target_mode'"
esac


#ToDo: Добавить вариант демонстрации свежезагруженных фоток
