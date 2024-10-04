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
DATE_SCRIPT="get_date.sh"
LOG_FILE="frame.log"

if [ ! -d "$DEMO_DIR" ]
then
  mkdir $DEMO_DIR
  unzip -d $DEMO_DIR $SRC_DIR/demo.zip
fi

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

SUDO_READY=`sudo cat /etc/sudoers | grep $USER | grep -E -e "NOPASSWD:\s*ALL" | wc -l`

if [ "$SUDO_READY" -eq 0 ]
then
  echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo
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
  rsync -av $SRC_DIR/$DATE_SCRIPT $BIN_DIR
fi
rsync -av $SRC_DIR/$CONF $CONF_DIR
rsync -av $SRC_DIR/$FONT $CONF_DIR

sudo ln -f -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
sudo localectl set-locale C.UTF-8

APT_OPTIONS="--allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages"
sudo apt-get --yes update
sudo apt-get --yes $APT_OPTIONS -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
sudo apt-get --yes $APT_OPTIONS -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

sudo apt-get -y install feh conky unclutter wmctrl exiftran exif exifprobe exiftool dos2unix

sudo apt-get -y install libimlib2-dev libheif-dev pkg-config build-essential
pushd ~
git clone https://github.com/vi/imlib2-heic.git
cd imlib2-heic/
make
sudo rsync -av heic.so `find /usr/lib -name 'loaders' | grep imlib`
popd

sudo systemctl enable chrony
sudo systemctl stop chrony
sudo systemctl start chrony
sudo chronyc makestep

sudo systemctl enable cron
sudo systemctl stop cron
sudo systemctl start cron


sudo systemctl stop unattended-upgrades
sudo apt-get -y purge unattended-upgrades
sudo chmod -x /etc/update-motd.d/40-orangepi-updates
sudo sed -i 's/Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades

sudo systemctl stop apt-daily.timer
sudo systemctl stop apt-daily-upgrade.timer
sudo systemctl stop apt-daily.service
sudo systemctl stop apt-daily-upgrade.service
sudo systemctl disable apt-daily.timer
sudo systemctl disable apt-daily-upgrade.timer
sudo systemctl mask apt-daily.service
sudo systemctl mask apt-daily-upgrade.service
sudo systemctl stop update-notifier-download.timer
sudo systemctl stop update-notifier-download.service
sudo systemctl disable update-notifier-download.service
sudo systemctl disable update-notifier-download.timer
sudo systemctl mask update-notifier-download.service

sudo systemctl daemon-reload
sudo systemctl reset-failed
sudo systemctl list-timers --all

sudo sed -i 's/^DPkg/#DPkg/' /etc/apt/apt.conf.d/99update-notifier
sudo sed -i 's/^APT/#APT/' /etc/apt/apt.conf.d/99update-notifier

sudo sed -i 's/Unattended-Upgrade "7"/Unattended-Upgrade "0"/' /etc/apt/apt.conf.d/02-orangepi-periodic

(crontab -l 2>/dev/null| grep -v $MAIN_SCRIPT; echo "* * * * * $BIN_DIR/$MAIN_SCRIPT >> $LOG_DIR/$LOG_FILE 2>&1") | crontab -

pkill conky
pkill unclutter
pkill feh

$BIN_DIR/$MAIN_SCRIPT

