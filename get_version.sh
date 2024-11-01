#!/bin/bash

history=$(git log -n 1000 --format=raw 2>/dev/null | grep author | sed 's/.*>\s*//' | sed 's/\s.*//' | xargs -I '{}' date -d @{} +'%Y.%m.%d')
version='0.0.0'

if [ -n "$history" ]
then
  last_date=$(echo "$history" | head -1)
  if [ -n "$last_date" ]
  then
    count=$(echo "$history" | grep $last_date | wc -l)
    if [ "$count" -gt "1" ]
    then
      version="$last_date-$count"
    else
      version="$last_date"
    fi
  fi
fi

echo $version
 

