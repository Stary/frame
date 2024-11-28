#!/bin/bash
DIR=$1

if [ -d "$DIR" ]
then
  sudo chown -R `whoami` $DIR
  find $DIR -type f | wc -l
  find $DIR -type d -regextype egrep -iregex ".*resized.*" -print0 | xargs -0 rm -rf
  find $DIR -type f -regextype egrep -not -iregex ".*(img|png|jpg|jpeg|heic)" -print0 | xargs -0 rm -rf
  find $DIR -type f | wc -l
  find $DIR -type d -empty -print -delete
  python3 sort.py $DIR
fi

