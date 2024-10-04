#!/bin/bash


if [ "$EUID" -eq 0 ]
  then echo "Please do not run the script as root"
  exit
fi

USER=`whoami`
SRC_DIR="$(cd $(dirname $(realpath "$0")); pwd -P)"

SUDO_READY=`sudo cat /etc/sudoers | grep $USER | grep -E -e "NOPASSWD:\s*ALL" | wc -l`

if [ "$SUDO_READY" -eq 0 ]
then
  echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo
fi

sudo ln -f -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
sudo localectl set-locale C.UTF-8

export DEBIAN_FRONTEND=noninteractive
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

$SRC_DIR/update.sh

