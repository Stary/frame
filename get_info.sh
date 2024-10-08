#!/bin/bash

f=$1

ts=''

if [ -s "$f" ]
then
  ts=`exiftool $1 2>/dev/null | grep -i date | grep -i -E -e "(create|gps|original)" | sort | head -1 | sed -E "s/^[^\:]+\:\s*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+).*/\1.\2.\3 \4:\5/"`
fi

ts=''

if [ -z "$ts" ]
then
    ts=`echo $1 | sed -E "s/^.*+\///g" | sed -E "s/\.[^\.]+$//" | sed -E "s/^.*?([0-9]{4})([0-9]{2})([0-9]{2})\_([0-9]{2})([0-9]{2})[0-9]+.*$/\1.\2.\3 \4:\5/g"`
fi


if [ ! -z "$ts" ]
then
  dow=`date --date $(sed "s/\./-/g" <<< "$ts" | sed "s/ .*//") +%a`
fi

place=$(~/bin/get_place.py $f)

echo $dow $ts $place

