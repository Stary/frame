#!/bin/bash

#Значения по-умолчанию, переопределяются значениями из файла frame.cfg в домашней папке пользователя либо в корне флэшки
DAY=800
NIGHT=2400
DELAY=55.0
RANDOM_ORDER=no
CONFIG='frame.cfg'
SLIDESHOW_DISPLAY=:0.0
FONT_DIR=/usr/share/fonts/truetype/freefont/
FONT='FreeMono/24'

USB_DIR=/media/usb

DIRS="$USB_DIR $HOME/frame $HOME/photo $HOME/demo2 $HOME/demo"
#DIRS="$HOME/test"
#DIRS="$HOME/demo2"
IMAGES_DIR=''
USER=`whoami`

if [ -s "$HOME/$CONFIG" ]
then
  source "$HOME/$CONFIG"
fi

if [ -s "$USB_DIR/$CONFIG" ]
then
  source "$USB_DIR/$CONFIG"
fi

echo "#Frame configuration
DAY=$DAY
NIGHT=$NIGHT
DELAY=$DELAY
RANDOM_ORDER=$RANDOM_ORDER
SLIDESHOW_DISPLAY=$SLIDESHOW_DISPLAY
FONT_DIR=$FONT_DIR
FONT=$FONT
" > $HOME/$CONFIG

export DISPLAY=$SLIDESHOW_DISPLAY
export XAUTHORITY=~/.Xauthority

unclutter_running=$(pgrep unclutter)
if [ -z "$unclutter_running" ]; then
  echo $unclutter_running
  pgrep unclutter
  unclutter -root >/dev/null 2>&1 &
#else
#  echo "unclutter's already running: $unclutter_running"
fi

###################### Mount USB ####################

sudo mkdir -p $USB_DIR

test_file='asDF4)SF4mADf.dat'

sudo touch $USB_DIR/$test_file || sudo umount $USB_DIR
sudo rm -f $USB_DIR/$test_file

for name in $(find /dev -name 'sd*1')
do
  n=$(mount | grep $name | wc -l)
  if [ $n -eq 0 ]
  then
    echo "Found external partition $name"
    sudo chown $USER:$USER $USB_DIR
    sudo chmod 777 $USB_DIR
    if sudo mount $name $USB_DIR -o umask=000,user,utf8; then
      for f in $(find  $USB_DIR -name '*.txt' -size -256 | grep -i wifi)
      do
        echo $f
        dos2unix $f
        wifi_ssid=""
        wifi_password=""
        for line in `head -10 $f`
        do
          if [ $line != '' ]; then
            echo $line
            if [ "$wifi_ssid" == '' ]; then
              wifi_ssid=$line
              wifi_nm_file="/etc/NetworkManager/system-connections/$wifi_ssid.nmconnection"
            else
              if [ "$wifi_password" == '' ]; then
                wifi_password=$line
                echo "WiFi: $wifi_ssid/$wifi_password"
                sudo nmcli device wifi connect "$wifi_ssid" password "$wifi_password" ifname wlan0
                echo "Created Network Manager config at $wifi_nm_file"
              fi
            fi
          fi
        done
      done
    fi
    pkill feh
#  else
#    echo "Partition $name is already mounted"
  fi
done

#####################################################

shopt -s extglob
TIME=$(date +%H%M | sed 's/^0\{1,3\}//')

NTP=$(chronyc tracking | grep -i status | grep -i normal | wc -l)

if (( $NTP == 0 ))
then
  echo "Синхронизация с NTP не работает, включаем принудительный дневной режим"
  TIME=$DAY
fi

if (( $TIME >= $DAY && $TIME < $NIGHT ))
then
#  pkill dclock
  pkill conky

  PID=$(pgrep exiftran)
  if [ ! -z "$PID" ]
  then
    echo "Exiftran is running, exiting"
    exit 0
  fi

  PID=$(pgrep feh)
  if [ -z "$PID" ]
  then
    date
    echo "Переход в дневной режим - запуск рамки"
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
      d=$(cat $PLAYLIST | sed -E -e "s/^.*\///g" | grep -E -e "^[0-9]{8}\_[0-9]{6}" | cut -c 1-8 | sort -u | shuf | head -1)
      if [ ! -z "$d" ]
      then
        echo "Найдем самую раннюю фотографию за дату $d:"
        f=`cat $PLAYLIST | grep "$d" | sort | head -1`
	#Если файлы имеют в имени дату - найдем случайный день и сдвинем начало презентации на первый файл от этого дня
        if [ ! -z "$f" ]
        then
          echo "Найден файл $f, начнем слайдшоу с него"
	  ORDER_OPTIONS=('-S' 'name' '--start-at' "$f")
        fi
      fi
    else
      echo "Пользователь задал случайный порядок отображения: $RANDOM_ORDER"
    fi
    set -x
    PID=$(pgrep feh)
    if [ -z "$PID" ]
    then
      feh -V -r -Z -F -Y -D $DELAY "${ORDER_OPTIONS[@]}" -C $FONT_DIR -e $FONT --info '~/bin/get_info.sh %F' --draw-tinted -f $PLAYLIST >> /var/log/frame/feh.log 2>&1 &
    else
      echo "Feh уже успел запуститься"
    fi
  fi
else
  pkill feh
#  PID=`pgrep dclock`
  PID=$(pgrep conky)
  if [ -z "$PID" ]
  then
    date
    echo "Переход в ночной режим - запуск часов"
    #Конфигурация часов сохранена в файле /home/pi/.config/conky/conky.conf
    conky
#    dclock -nobell -miltime -tails -noscroll -blink -nofade -noalarm -thickness 0.12 -slope 70.0 -bd "black" -bg "black" -fg "darkorange" -led_off "black" &
    sleep 2s
    #unclutter -root 2>&1 >/dev/null &
  fi
  wmctrl -r conky -b add,fullscreen,above
fi

