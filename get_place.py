#!/bin/env python3

import subprocess
import sys
import os
import re

import geo

path_to_file = sys.argv[1] if len(sys.argv) > 1 else ''

#path_to_file = '/Users/sergey/Photo/icloud/20240922_160133.heic'
#path_to_file = '/Users/sergey/Photo/poi/Маркиза.HEIC'

if os.path.isfile(path_to_file):
    try:
        place_descr = ''
        place_radius = 1.0
        filename = os.path.basename(path_to_file)
        m = re.match(r"(.*?\D)[\s_]*(\d+)\s*(km|m)\.([a-z]+)", filename, flags=re.IGNORECASE)
        if m:
            #print(f"{m.group(0)}|{m.group(1)}|{m.group(2)}|{m.group(3)}|{m.group(4)}")
            place_descr = m.group(1)
            place_radius = float(m.group(2)) * (0.001 if m.group(3).lower() == 'm' else 1)
        output=subprocess.run(['exiftool', '-n', path_to_file], stdout=subprocess.PIPE).stdout #.decode('utf-8')
        try:
            output_str = output.decode('utf-8')
        except UnicodeDecodeError as e:
            output_str = output.decode('ascii')
        exif = dict()
        for line in output_str.splitlines():
            attr = re.split(r'\s*:\s+', line, maxsplit=1)
            if len(attr) == 2:
                exif[attr[0]] = attr[1]
        if 'GPS Latitude' in exif and 'GPS Longitude' in exif:
            try:
                latitude = float(exif['GPS Latitude'])
                longitude = float(exif['GPS Longitude'])
                if place_descr is not None and place_descr != '':
                    geo.set_place_descr(latitude, longitude, place_descr, place_radius)
                else:
                    place_descr = geo.get_place_descr(latitude, longitude)
                print(f"{place_descr}")
            except ValueError:
                pass
    except Exception as e:
        print(f"Exception occured while processing file {path_to_file}: {repr(e)}")

#cmd = f"find -E {dir} -size +100k -iregex '.*\.(img|png|jpg|jpeg)$' -exec exiftool -n '\{\}' \; | grep -E -e 'GPS\s+Position'"

