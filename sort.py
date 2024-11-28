import copy
import os
import hashlib
import re
import platform
import time
import subprocess
import traceback

import geo
import json
import sys

meta = dict()


def save_meta(source_dir):
    global meta
    with open(os.path.join(source_dir,'photo.json'), 'w', encoding='utf8') as json_file:
        json.dump(meta, json_file, indent=4, sort_keys=True, ensure_ascii=False)


def creation_date(path_to_file, force_exif=False):
    """
    Extract creation date from a file, either from its filename (if it starts with a date in the format YYYYMMDD_HHMMSS)
    or from its EXIF metadata (if available).

    :param path_to_file: path to the file
    :param force_exif: if True, ignore filename and force extraction from EXIF metadata
    :return: creation date as a Unix timestamp, or None if extraction failed
    """
    global meta

    filename = os.path.basename(path_to_file)

    if filename not in meta:
        meta[path_to_file] = dict()

    print(f"{path_to_file=} {filename=}")
    if not force_exif and re.match(r'^20[0-9]{6}\_[0-9]{6}', filename):
        time_obj = time.strptime(filename[0:15], '%Y%m%d_%H%M%S')
        print(f"Timestamp extracted from filename {filename}: {time_obj}")
        return time.mktime(time_obj)

    try:
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
            #print(f"{latitude=}, {longitude=}")
            meta[path_to_file]['lat'] = latitude
            meta[path_to_file]['lon'] = longitude
            meta[path_to_file]['address'] = geo.get_place_descr(latitude, longitude, raw=True)

        for p in ('Create Date', 'Date Created', 'Date/Time Original', 'GPS Date/Time', 'File Modification Date/Time'):
            if p in exif:
                try:
                    time_obj = time.strptime(exif[p][0:19], '%Y:%m:%d %H:%M:%S')
                    print(f"EXIF: {p} = {exif[p]} = {time_obj}")
                    if int(time_obj.tm_year) >= 1990:
                        meta[path_to_file]['created'] = exif[p][0:19]
                        return time.mktime(time_obj)
                except ValueError as ve:
                    pass
    except Exception as e:
        print(f"Exception occured for file {path_to_file}: {traceback.format_exc()}")

    if platform.system() in ['Windows', 'Linux']:
        return os.path.getctime(path_to_file)
    else:
        stat = os.stat(path_to_file)
        try:
            return stat.st_birthtime
        except AttributeError:
            # We're probably on Linux. No easy way to get creation dates here,
            # so we'll settle for when its content was last modified.
            return stat.st_mtime

source_dir=''
dirs = ["/Users/sergey/Photo/icloud", "/home/orangepi/frame"]

if len(sys.argv) > 1 and os.path.isdir(sys.argv[1]):
    source_dir = sys.argv[1]
else:
    for d in dirs:
        if os.path.isdir(d):
            source_dir = d
            break
count = 0
known_hash = dict()
known_name = dict()
known_ct = dict()
files = dict()


def process_dir(cur_dir, target_dir):
    global count
    global known_hash
    global known_name
    for i in sorted(os.scandir(cur_dir), key=lambda e: e.name):
        if i.is_file():
            count += 1
            path = i.path.split(os.sep)[:-1]
            name_parts = i.name.split('.')
            ext_i = -1
            name = '.'.join(name_parts[:ext_i])
            ext = '.'.join(name_parts[ext_i:]).lower()
            hash = hashlib.md5(open(i.path, 'rb').read()).hexdigest()
            #hash = uuid.uuid4().hex
            #name2 = re.sub(r'[\W_ийеё]+', '', name.lower())

            full_path = i.path
            ctime = time.localtime(creation_date(full_path, force_exif=True))
            ct = f"{ctime.tm_year}{ctime.tm_mon:02d}{ctime.tm_mday:02d}_{ctime.tm_hour:02d}{ctime.tm_min:02d}{ctime.tm_sec:02d}"
            suffix = '.' + ext if ext != '' else ''
            suffix_uniq = '_' + str(count) + suffix
            new_name = os.path.join(cur_dir, f"{ct}{suffix}")
            new_name_uniq = os.path.join(cur_dir, f"{ct}{suffix_uniq}")

            if hash in known_hash:
                print(f"{count}. {full_path} is a copy of {known_hash[hash]}")
                os.remove(full_path)
            else:
                known_hash[hash] = full_path

                if new_name != full_path:
                    if os.path.isfile(new_name):
                        print(f"{count}!{full_path} => {new_name_uniq}")
                        os.rename(full_path, new_name_uniq)
                        meta[new_name_uniq] = copy.deepcopy(meta[full_path])
                    else:
                        print(f"{count}.{full_path} => {new_name}")
                        os.rename(full_path, new_name)
                        meta[new_name] = copy.deepcopy(meta[full_path])
                    del meta[full_path]

            # files[full_path] = {"ct": ct, "ext": ext.lower(), "hash": hash, "path": os.sep.join(path)}
            if count % 100 == 0:
                print(f"======== {count} files processed =======")
                save_meta(target_dir)
        elif i.is_dir():
            process_dir(i.path, target_dir)

process_dir(source_dir, source_dir)

save_meta(source_dir)
        #print(json.dumps(meta, indent=4, sort_keys=True, ensure_ascii=False))

exit(0)