#!/bin/bash


REPORTS_EMAIL='megatestbot@gmail.com'
report_zip="/tmp/report_$(date '+%Y%m%d_%H%M%S').zip"
#ToDo: add send the report with zip attached to REPORTS_EMAIL

TMP_LOG_DIR=$(mktemp -d /tmp/frame_log.XXXXXX)
if [ ! -d "$TMP_LOG_DIR" ]; then
  echo "ERROR: Could not create temporary directory" >&2
  exit 1
fi

while read -r log_file; do
  mkdir -p $TMP_LOG_DIR/log
  file="${log_file##*/}"
  tail -10000 $log_file > "$TMP_LOG_DIR/log/$file" 
done <<< "$(find /var/log/frame -type f -name '*.log')"

cp -R /tmp/frame "$TMP_LOG_DIR"
cp ~/frame.cfg "$TMP_LOG_DIR"
ls -alR ~ > "$TMP_LOG_DIR/ls.home"
ls -alR /media > "$TMP_LOG_DIR/ls.media"
mount > "$TMP_LOG_DIR/mount"
dmesg > "$TMP_LOG_DIR/dmesg"
crontab -l > "$TMP_LOG_DIR/crontab"
ifconfig -a > "$TMP_LOG_DIR/ifconfig"
sudo nmcli d > "$TMP_LOG_DIR/nmcli.d"
sudo nmcli d wifi > "$TMP_LOG_DIR/nmcli.d.wifi"
sudo nmcli c > "$TMP_LOG_DIR/nmcli.c"
iptables -L -n > "$TMP_LOG_DIR/iptables"


zip -r $report_zip $TMP_LOG_DIR

# Get external IP address
EXTERNAL_IP=$(curl -s https://ipecho.net/plain)
if [ -z "$EXTERNAL_IP" ]
then
  echo "Failed to get external IP address."
  exit
fi

# Check if mutt command is available, if not - install it
if ! command -v mutt &> /dev/null; then
    echo "Mail agent is not installed."
    exit
fi

# Send email with the report attached
echo "Frame logs report $(date '+%Y-%m-%d %H:%M:%S')" | mutt -s "Frame Logs Report from $EXTERNAL_IP" -a "$report_zip" -- "$REPORTS_EMAIL"

rm -rf "$TMP_LOG_DIR"
rm -rf "$report_zip"
