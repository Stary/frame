#!/bin/bash

f=$1

ts=''

export LC_ALL=ru_RU.UTF-8
export LANG=ru_RU.UTF-8

if [ -s "$f" ]
then
  ts=$(exiftool "$1" 2>/dev/null | grep -i date | grep -i -E -e "(create|gps|original)" | sort | head -1 | sed -E "s/^[^\:]+\:\s*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+)[^0-9]*([0-9]+).*/\1-\2-\3 \4:\5:\6/")
fi

if [ -z "$ts" ]
then
  ts=$(echo $1 | sed -E "s/^.*\///g" | sed -E "s/\.[^\.]+$//" | grep -E -e "^[0-9_]+$" | sed -E "s/^.*?([0-9]{4})([0-9]{2})([0-9]{2})\_([0-9]{2})([0-9]{2})([0-9]{2}).*$/\1-\2-\3 \4:\5:\6/g")
fi

if [ -n "$ts" ]
then
  ts=$(date --date "$ts" +'%a %d %B %Y %R' 2>/dev/null)
fi

place=$(~/bin/get_place.py "$f")

if [ -n "$ts" ]
then
  echo $ts
fi

if [ -n "$place" ]
then
  echo $place
fi
