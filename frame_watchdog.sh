#!/bin/bash

#Проверим, чтобы не был запущен другой экземпляр скрипта
if pidof -o %PPID -x -- "$0" >/dev/null; then
  printf >&2 '%s\n' "ERROR: Script $0 already running"
  exit 1
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

CLOCK_COLOR=C8320A
CLOCK_SIZE=560
CLOCK_OFFSET=40
CLOCK_VOFFSET=320

USB_DIR=/media/usb
BIN_DIR=$HOME/bin
LOG_DIR=/var/log/frame
CONKY_CONF=$HOME/.config/conky/conky.conf
CONKY_CONF_TEMPLATE=$HOME/.config/conky/conky.conf.template

DIRS="$USB_DIR /media/photo $HOME/photo /media/demo $HOME/demo"
IMAGES_DIR=''
USER=$(whoami)

RESTART_SLIDESHOW_AFTER=120

WIFI_DEV='wlan0'
WIFI_MAC=$((16#$(ifconfig $WIFI_DEV 2>/dev/null | awk '/ether/ {print $2}' | cut -d ':' -f 5-6 | sed 's/://g' | tr a-z A-Z)))
WIFI_AP_PASSWORD_FILE="$HOME/user.dat"

WIFI_SSID=''
WIFI_PASSWORD=''
WIFI_ERROR=''

function internet { wget -q --spider http://google.com 2>/dev/null && chronyc tracking | grep -i status | grep -i normal | wc -l; }

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
  #Проверим подключение к Интернету, если все уже работает - просто выходим
  if [ "X$(internet)" != "X1" ]
  then
    echo "Интернет недоступен, подключаемся к сети WiFi '$WIFI_SSID'"
    pkill nm-applet
    res=$(sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" ifname $WIFI_DEV 2>&1)
    echo "Res: $res"
    if [[ $res == *"property is invalid"* ]] || [[ $res == *"not provided"* ]]
    then
      WIFI_ERROR="Wrong password $WIFI_PASSWORD"
      WIFI_PASSWORD=''
    elif [ "X$(internet)" != "X1" ]
    then
      network_available=$(sudo nmcli dev wifi | grep -E -e "\s$WIFI_SSID\s")
      all_networks=$(sudo nmcli dev wifi | head -10)
      if [ -z "$network_available" ] && [ -n "$all_networks" ]
      then
        WIFI_ERROR="Network $WIFI_SSID not found"
        echo "All networks:"
        echo "$all_networks"
      else
        echo "Интернет все еще недоступен, перегружаем NetworkManager"
        sudo systemctl restart NetworkManager
        sleep 5
        if [ "X$(internet)" != "X1" ]
        then
          echo "Перезагрузка NetworkManager не помогла, повторно пытаемся подключиться к сети WiFi '$WIFI_SSID'"
          res=$(sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" ifname $WIFI_DEV 2>&1)
          echo "Res: $res"
	        sleep 5
	        if [ "X$(internet)" != "X1" ]
	        then
	          echo "Подключение так и не установлено. Возможно, поможет полная перезагрузка"
	          echo "Доступные WiFi-сети:"
	          sudo nmcli dev wifi list
	          echo "Подключения:"
            sudo nmcli con
            echo "Устройства:"
	          sudo nmcli dev
	        fi
        fi
      fi
    else
      echo "Подключение к Интернету установлено"
      WIFI_ERROR=''
    fi
  else
    #echo "Интернет доступен, изменение настроек не требуется"
    WIFI_ERROR=''
  fi
fi

read -r -d '' config << EOM
################################
#Frame configuration
################################

VERSION=_VERSION_

#Разовое автоматическое обновление, для разрешения выставить в yes. После применения автоматически сбрасывается в no
UPDATE=no

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
#Ошибка подключения к сети WiFi, автоматически обнуляется после успешного подключения
WIFI_ERROR=$WIFI_ERROR
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

