import traceback

import redis
import subprocess
import sys
import os
import re
import requests


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def set_place_descr(lat, lon, descr, radius = 100.0):
    global r
    if r is not None:
        try:
            r.geoadd('user_places', [lon, lat, f"{descr}|{radius:.2f}"])
            print(f"Added point {descr} at ({lat:.6f},{lon:.6f})")
        except Exception as e:
            eprint(f"Exception: {traceback.format_exc()}")


def get_place_descr(lat, lon):
    global r
    place_descr = None
    if r is not None:
        try:
            if hasattr(r, 'geosearch'):
                user_places = r.geosearch(
                    name='user_places',
                    longitude=lon,
                    latitude=lat,
                    radius=1000,
                    unit='km',
                    withdist=True,
                    sort='ASC')
            else:
                user_places = r.georadius('user_places', lon, lat, withdist=True, sort='ASC')

            for pr, dist in user_places:
                descr, radius_str = pr.split('|')
                try:
                    radius = float(radius_str)
                except Exception as e:
                    radius = 10.0

                if dist < radius:
                    place_descr = descr
                    break
                print(f"{descr=} {radius=} {dist=}")

        except Exception as e:
            eprint(f"Exception: {traceback.format_exc()}")

        try:
            if place_descr is None or place_descr == '':
                if hasattr(r,'geosearch'):
                    cached_res = r.geosearch(
                        name='nominatim',
                        longitude=lon,
                        latitude=lat,
                        radius=1,
                        unit='km',
                        withdist=True,
                        sort='ASC')
                else:
                    cached_res = r.georadius('nominatim', lon, lat, withdist=True, sort='ASC')

                if cached_res is not None and len(cached_res) > 0:
                    print(f"got from cache: {cached_res}")
                    place_descr = cached_res[0][0]
        except Exception as e:
            eprint(f"Exception: {traceback.format_exc()}")

    if place_descr is None or place_descr == '':
        try:
            url = f'https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json&accept-language=ru&zoom=15'
            print(url)
            req_res = requests.get(url=url)
            result_json = req_res.json()
            print(f"got from service {result_json}")
            if result_json is not None and 'display_name' in result_json:
                place_descr = result_json['display_name']
                if r is not None:
                    r.geoadd('nominatim', [lon, lat, place_descr])
        except Exception as e:
            eprint(f"Exception: {traceback.format_exc()}")

    return place_descr


try:
    r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)
except Exception as e:
    eprint(f"Exception: {traceback.format_exc()}")
    r = None

path_to_file = sys.argv[1] if len(sys.argv) > 1 else ''

#path_to_file = '/Users/sergey/Photo/icloud/20240922_160133.heic'
#path_to_file = '/Users/sergey/Photo/ref/Тихая Ладога 1km.heic'

if os.path.isfile(path_to_file):
    place_descr = ''
    place_radius = 1.0
    filename = os.path.basename(path_to_file)
    #print(f"{filename=}")
    m = re.match(r"(.*\S)[\s\_]*(\d+)(km|m)\.([a-z]+)", filename)
    if m:
        print(f"{m.group(0)}|{m.group(1)}|{m.group(2)}|{m.group(3)}|{m.group(4)}")
        descr = m.group(1)
        radius = float(m.group(2)) * (0.001 if m.group(3).lower() == 'm' else 1)
    #exit(0)
    output=subprocess.run(['exiftool', '-n', path_to_file], stdout=subprocess.PIPE).stdout.decode('utf-8')
    exif = dict()
    for line in output.splitlines():
        attr = re.split(r'\s*:\s+', line, maxsplit=1)
        if len(attr) == 2:
            exif[attr[0]] = attr[1]
            #print(f"{attr[0]} = {attr[1]}")
    if 'GPS Latitude' in exif and 'GPS Longitude' in exif:
        latitude = float(exif['GPS Latitude'])
        longitude = float(exif['GPS Longitude'])
        if place_descr is not None and place_descr != '':
            set_place_descr(latitude, longitude, place_descr, place_radius)
        else:
            place_descr = get_place_descr(latitude, longitude)
        print(f"{place_descr}")

#cmd = f"find -E {dir} -size +100k -iregex '.*\.(img|png|jpg|jpeg)$' -exec exiftool -n '\{\}' \; | grep -E -e 'GPS\s+Position'"

