#!/bin/bash
DIR=$1

if [ -d "$DIR" ]
then
  sudo chown -R `whoami` $DIR
  echo "Количество файлов перед очисткой: $(find $DIR -type f | wc -l)"
  find $DIR -type d -regextype egrep -iregex ".*resized.*" -print0 | xargs -0 rm -rf
  find $DIR -type f -regextype egrep -not -iregex ".*(img|png|jpg|jpeg|heic)" -print0 | xargs -0 rm -rf
  find $DIR -type f | wc -l
  echo "Количество файлов после удаления файлов, отличных от изображений: $(find $DIR -type f | wc -l)"
  python3 sort.py $DIR
  find $DIR -type d -empty -print -delete
  echo "Количество файлов после удаления дубликатов: $(find $DIR -type f | wc -l)"
fi

