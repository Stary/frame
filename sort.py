import os
import hashlib
import re
import platform
import time
import subprocess
import geo

def creation_date(path_to_file, force_exif=False):

    filename = os.path.basename(path_to_file)
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
                print(f"{attr[0]} = {attr[1]}")
        for p in ('Create Date', 'Date Created', 'Date/Time Original', 'GPS Date/Time'):
            if p in exif:
                try:
                    time_obj = time.strptime(exif[p][0:19], '%Y:%m:%d %H:%M:%S')
                    print(f"EXIF: {p} = {exif[p]} = {time_obj}")
                    if int(time_obj.tm_year) >= 1990:
                        return time.mktime(time_obj)
                except ValueError as ve:
                    pass
    except Exception as e:
        print(f"Exception occured for file {path_to_file}")

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


#print(time.strptime('1990-01-01', '%Y-%m-%d'))
#exit(0)

#print(time.localtime(creation_date('/Users/sergey/Photo/icloud/8396.HEIC')))
#print(creation_date('/Users/sergey/Photo/icloud/8396.HEIC'))
#exit(0)

source_dir=''
dirs = ["/Users/sergey/Photo/icloud_test", "/home/orangepi/frame"]
for d in dirs:
    if os.path.isdir(d):
        source_dir = d
count = 0
known_hash = dict()
known_name = dict()
known_ct = dict()
files = dict()


for i in sorted(os.scandir(source_dir), key=lambda e: e.name):
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
        #print(f"{full_path} {ctime=}")
        #name3 = f"{ctime.tm_year}{ctime.tm_mon:02d}{ctime.tm_mday:02d}_{ctime.tm_hour:02d}{ctime.tm_min:02d}{ctime.tm_sec:02d}"
        ct = f"{ctime.tm_year}{ctime.tm_mon:02d}{ctime.tm_mday:02d}_{ctime.tm_hour:02d}{ctime.tm_min:02d}{ctime.tm_sec:02d}"
        suffix = '.' + ext if ext != '' else ''
        suffix_uniq = '_' + str(count) + suffix
        new_name = os.path.join(os.sep.join(path), f"{ct}{suffix}")
        new_name_uniq = os.path.join(os.sep.join(path), f"{ct}{suffix_uniq}")

        if hash in known_hash:
            print(f"{count}. {full_path} is a copy of {known_hash[hash]}")
            os.remove(full_path)
        else:
            known_hash[hash] = full_path

            if new_name != full_path:
                if os.path.isfile(new_name):
                    print(f"{count}!{full_path} => {new_name_uniq}")
                    os.rename(full_path, new_name_uniq)
                else:
                    print(f"{count}.{full_path} => {new_name}")
                    os.rename(full_path, new_name)

       # files[full_path] = {"ct": ct, "ext": ext.lower(), "hash": hash, "path": os.sep.join(path)}
        if count % 100 == 0:
            print(f"{count} files processed")

exit(0)

for file in files.copy():
    hash = files[file]["hash"]
    if hash in known_hash:
        print(f"!!! {file} {ct} {known_hash[hash]} {files[known_hash[hash]]['ct']} {hash}")
        os.remove(file)
        del files[file]
    else:
        known_hash[hash] = file

for file, p in sorted(files.items(), key=lambda k: k[1]["ct"] + k[1]["hash"]):
    hash = p["hash"]
    ct = p["ct"]
    path = p["path"]
    ext = p["ext"]
    suffix = ''
    if ct in known_ct:
        cnt = known_ct[ct]
        suffix = f"_{cnt}"
        known_ct[ct] += 1
    else:
        known_ct[ct] = 1
    if ext != '':
        suffix += '.' + ext
    file_new = os.path.join(path, f"{ct}{suffix}")
    # print(f"{file=} => {file_new=} {path=} {ct=} {suffix=} {ext=} {hash=}")
    if file_new != file:
        print(f"Let's rename {file} => {file_new}")
        os.rename(file, file_new)
# print(files)