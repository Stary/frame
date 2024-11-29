#!/bin/bash

source_dir=$(echo "$1" | sed 's:/*$::')
target_dir=$(echo "$2" | sed 's:/*$::')

function usage { echo Usage: $0 source_dir target_dir; }

error=''

if [ -z "$source_dir" ]
then
  echo "Source dir not specified"
  error=-1
elif [ ! -d "$source_dir" ]
then
  echo "Source dir $source_dir doesn't exist"
  error=-1
fi

if [ -z "$target_dir" ]
then
  echo "Target dir not specified"
  error=-1
elif [ ! -d "$target_dir" ]
then
  echo "Target dir $target_dir doesn't exist"
  error=-1
elif [ "X$source_dir" == "X$target_dir" ]
then
  echo "Target dir must not be equal to the source dir $source_dir"
  error=-1
fi

if [ -n "$error" ]
then
  usage
  exit -1
fi

echo "Let's sync from $source_dir to $target_dir"

shopt -u nocasematch
shopt -u nocaseglob

file_counter=0
#Копируем только файлы с разрешениями, соответствующими типам изображений, и размером не менее 100кб
find -E $source_dir -type f -size +100k -iregex ".*\.(img|png|jpg|jpeg|heic)" -print | sed "s|^$source_dir||" | sed "s|^/||" | grep -E -e "^(20|Canon)" | grep -v -i 'resized' | sort |\
while read line
do
  let "file_counter++"
  file="${line##*/}" 
  path="${line%/*}"
  mkdir -p "$target_dir/$path"
  echo "$file_counter. $source_dir/$path/$file => $target_dir/$path/$file" 
  rsync -a "$source_dir/$path/$file" "$target_dir/$path/$file"
#  if [ ! -s "$target_dir/$path/$file" ]
#  then
#    echo "COPY: $source_dir/$path/$file $target_dir/$path/$file"
#    cp -f "$source_dir/$path/$file" "$target_dir/$path/$file"
#  fi
done

#Удаление пустых папок
find "$target_dir" -type d -empty -print -delete

#Автоповорт фоток, если есть соответствующие данные в EXIF
find -E "$target_dir" -type f -size +100k -iregex ".*\.(img|png|jpg|jpeg|heic)" -print -exec exiftran -ai '{}' \;

