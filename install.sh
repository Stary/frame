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
MEDIA_DIR="$HOME_DIR/frame"
CONF_DIR="$HOME_DIR/.config/conky"
BIN_DIR="$HOME_DIR/bin"
LOG_DIR="/var/log/frame"

CONF="conky.conf"
FONT="UbuntuThin.ttf"
MAIN_SCRIPT="frame_watchdog.sh"
LOG_FILE="frame.log"

SUDO_READY=`sudo cat /etc/sudoers | grep $USER | grep -E -e "NOPASSWD:\s*ALL" | wc -l`

if [ "$SUDO_READY" -eq 0 ]
then
  echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo
fi

for d in $MEDIA_DIR $CONF_DIR $BIN_DIR $LOG_DIR
do
  echo $d
  sudo mkdir -p $d
  sudo chown -R $USER $d
done

if [ $SRC_DIR != $BIN_DIR ];
then
  rsync -av $SRC_DIR/$MAIN_SCRIPT $BIN_DIR
fi
rsync -av $SRC_DIR/$CONF $CONF_DIR
rsync -av $SRC_DIR/$FONT $CONF_DIR

sudo ln -f -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime

sudo apt-get -y update
sudo apt-get -y upgrade

sudo apt-get -y install feh conky unclutter wmctrl exiftran exif exifprobe

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

