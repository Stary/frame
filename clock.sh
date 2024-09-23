#!/bin/bash

export DISPLAY=:0

killall conky

conky

sleep 2

unclutter -root 2>&1 >/dev/null &

wmctrl -r conky -b add,fullscreen,above

