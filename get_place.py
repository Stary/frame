#!/bin/env python3

import subprocess
import sys
import os
import re

import geo

path_to_file = sys.argv[1] if len(sys.argv) > 1 else ''

#path_to_file = '/Users/sergey/Photo/icloud/20240922_160133.heic'
#path_to_file = '/Users/sergey/Photo/ref/Тихая Ладога 1km.heic'

if os.path.isfile(path_to_file):
    place_descr = ''
    place_radius = 1.0
    filename = os.path.basename(path_to_file)
    m = re.match(r"(.*\S)[\s\_]*(\d+)(km|m)\.([a-z]+)", filename)
    if m:
        print(f"{m.group(0)}|{m.group(1)}|{m.group(2)}|{m.group(3)}|{m.group(4)}")
        descr = m.group(1)
        radius = float(m.group(2)) * (0.001 if m.group(3).lower() == 'm' else 1)
    output=subprocess.run(['exiftool', '-n', path_to_file], stdout=subprocess.PIPE).stdout.decode('utf-8')
    exif = dict()
    for line in output.splitlines():
        attr = re.split(r'\s*:\s+', line, maxsplit=1)
        if len(attr) == 2:
            exif[attr[0]] = attr[1]
    if 'GPS Latitude' in exif and 'GPS Longitude' in exif:
        latitude = float(exif['GPS Latitude'])
        longitude = float(exif['GPS Longitude'])
        if place_descr is not None and place_descr != '':
            geo.set_place_descr(latitude, longitude, place_descr, place_radius)
        else:
            place_descr = geo.get_place_descr(latitude, longitude)
        print(f"{place_descr}")

#cmd = f"find -E {dir} -size +100k -iregex '.*\.(img|png|jpg|jpeg)$' -exec exiftool -n '\{\}' \; | grep -E -e 'GPS\s+Position'"

