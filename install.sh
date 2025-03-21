#!/bin/bash


#./install.sh 2>&1 | tee  ~/install.$(date +'%Y%m%d_%H%M%S').log

if [ "$EUID" -eq 0 ]
  then echo "Please do not run the script as root"
  exit
fi

USER=`whoami`
SRC_DIR="$(cd $(dirname $(realpath "$0")); pwd -P)"
#BG_IMAGES_DIR=$HOME/bg
SUDO_FILE="/etc/sudoers.d/$USER"
RELEASE=$(lsb_release -c | sed 's/.*\:\s*//')

VERSION_SCRIPT='get_version.sh'

echo "+============================+"
echo "|   Advanced Photo Frame     |"
echo "+============================+"

$SRC_DIR/$VERSION_SCRIPT

if [ ! -s "$SUDO_FILE" ]
then
  echo "$USER ALL=(ALL) NOPASSWD: ALL" > /tmp/sudo$USER
  echo $USER | sudo -S chown root:root /tmp/sudo$USER
  echo $USER | sudo -S mv /tmp/sudo$USER $SUDO_FILE
fi

#gsettings set org.gnome.desktop.background picture-uri ""
#gsettings set org.gnome.desktop.background picture-uri-dark ""
#gsettings set org.gnome.desktop.background primary-color '#000000'
#if [ ! -d "$BG_IMAGES_DIR" ]
#then
#  mkdir -p "$BG_IMAGES_DIR"
#  wget -O "$BG_IMAGES_DIR/bg.jpg" https://images8.alphacoders.com/137/1374345.jpg
#  wget -O "$BG_IMAGES_DIR/bg2.jpg" https://quietharbor.net/static/bg.jpg
#fi
#bgimage=$(find $BG_IMAGES_DIR -type f -size +100k | grep -i -E -e '(img|png|jpg|jpeg|heic)' | shuf -n 1)
#if [ "$bgimage" != "" ]
#then
#  echo Changing background to $bgimage
#  for p in $(xfconf-query -c xfce4-desktop -l | grep -i last-image)
#  do
#    xfconf-query -c xfce4-desktop -p "$p" -s "$bgimage"
#  done
#fi

sudo ln -f -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
sudo localectl set-locale C.UTF-8

sudo systemctl stop unattended-upgrades
sudo apt-get -y purge unattended-upgrades update-manager
sudo chmod -x /etc/update-motd.d/40-orangepi-updates
sudo sed -i 's/Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
sudo apt-get --yes autoremove

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
#sudo systemctl list-timers --all

sudo sed -i 's/^DPkg/#DPkg/' /etc/apt/apt.conf.d/99update-notifier
sudo sed -i 's/^APT/#APT/' /etc/apt/apt.conf.d/99update-notifier
sudo sed -i -r 's/Unattended-Upgrade "[0-9]+"/Unattended-Upgrade "0"/' /etc/apt/apt.conf.d/02-orangepi-periodic

export DEBIAN_FRONTEND=noninteractive
#sudo apt-get --yes update
#sudo apt-get --yes upgrade
#sudo apt-get --yes dist-upgrade
APT_OPTIONS="--allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages"
sudo apt-get --yes update
sudo apt-get --yes $APT_OPTIONS -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
sudo apt-get --yes $APT_OPTIONS -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

sudo apt-get -y install feh
#package conky moved to conky-all in Ubuntu 22.04 noble
sudo apt-get -y install conky || sudo apt-get -y install conky-all
sudo apt-get -y install unclutter wmctrl exiftran exif exifprobe exiftool dos2unix python3-redis python3-requests

sudo apt-get -y install libimlib2-dev libheif-dev pkg-config build-essential

heic_loader_installed=$(find /usr/lib -name 'heic.so' | grep loaders | grep imlib | wc -l)
if [ "$heic_loader_installed" -eq 0 ]
then
  pushd ~
  git clone https://github.com/vi/imlib2-heic.git
  cd imlib2-heic/
  make
  sudo rsync -av heic.so `find /usr/lib -name 'loaders' | grep imlib`
  popd
  rm -rf ~/imlib2-heic
else
  echo "heic imlib loader is already installed"
fi

sudo apt-get -y remove python3-update-manager update-manager-core


sudo systemctl enable chrony
sudo systemctl stop chrony
sudo systemctl start chrony
sudo chronyc makestep

sudo systemctl enable cron
sudo systemctl stop cron
sudo systemctl start cron


keydb_installed=$(sudo dpkg -l keydb-server 2>/dev/null | wc -l)
if [ "$keydb_installed" -ne 0 ]
then
  sudo systemctl enable keydb-server
  sudo systemctl start keydb-server
  keydb_running=$(pgrep keydb-server)
  if [ -z "$keydb_running" ]
  then
    sudo systemctl status keydb-server | tail -20
    echo "Something wrong with KeyDB, let's try to reinstall it"
    sudo dpkg -P keydb-server
    keydb_installed=0
  fi
fi

if [ "$keydb_installed" -eq 0 ]
then
  BASE_URL=https://download.keydb.dev/pkg/open_source/deb/ubuntu22.04_jammy/arm64/keydb-latest/
  for f in $(wget -O - $BASE_URL 2>&1 | grep -i 'href="keydb' | grep -v sentinel | sed 's/.*href=\"//i' | sed 's/\".*//' | sort -r)
  do
    echo "f=$f"
    wget -O /tmp/$f $BASE_URL/$f
    sudo dpkg -i /tmp/$f
    rm -f /tmp/$f
  done
else
  echo "KeyDB is already installed"
fi
if [ ! -s /etc/keydb/keydb.conf ]
then
  sudo mv -f /etc/keydb/keydb.conf.dpkg-new /etc/keydb/keydb.conf
fi

sudo systemctl enable keydb-server
sudo systemctl start keydb-server
sudo systemctl status keydb-server | tail -20

#sudo locale-gen 'C.UTF-8'
#sudo dpkg-reconfigure locales


ssh=$(pgrep sshd)

if [ -z "$ssh" ]
then
  sudo apt -y remove ssh
  sudo rm -f /etc/ssh/ssh_host*
  sudo apt -y install ssh
  sudo dpkg-reconfigure openssh-server
  sudo systemctl enable ssh
  sudo systemctl start ssh
  sudo systemctl status ssh
fi

$SRC_DIR/update.sh force
