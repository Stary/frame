import os
import hashlib
import re
import platform
import time


def creation_date(path_to_file):
    """
    Try to get the date that a file was created, falling back to when it was
    last modified if that isn't possible.
    See http://stackoverflow.com/a/39501288/1709587 for explanation.
    """

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
dirs = ["/Users/sergey/Photo/iCloud", "/home/sergey/photo/icloud", "/home/orangepi/frame"]
for d in dirs:
    if os.path.isdir(d):
        source_dir = d
count = 0
known_hash = dict()
known_name = dict()
known_ct = dict()
files = dict()

for i in os.scandir(source_dir):
    if i.is_file():
        count += 1
        path = i.path.split(os.sep)[:-1]
        name_parts = i.name.split('.')
        ext_i = -1
        name = '.'.join(name_parts[:ext_i])
        ext = '.'.join(name_parts[ext_i:]).lower()
        hash = hashlib.md5(open(i.path, 'rb').read()).hexdigest()
        name2 = re.sub(r'[\W_ийеё]+', '', name.lower())

        full_path = i.path
        ctime = time.localtime(creation_date(full_path))
        name3 = f"{ctime.tm_year}{ctime.tm_mon:02d}{ctime.tm_mday:02d}_{ctime.tm_hour:02d}{ctime.tm_min:02d}{ctime.tm_min:02d}"
        ct = f"{ctime.tm_year}{ctime.tm_mon:02d}{ctime.tm_mday:02d}_{ctime.tm_hour:02d}{ctime.tm_min:02d}{ctime.tm_min:02d}"
        files[full_path] = {"ct": ct, "ext": ext, "hash": hash, "path": os.sep.join(path)}
        if count % 100 == 0:
            print(f"{count} files processed")

for file, p in sorted(files.items(), key=lambda k: k[1]["ct"] + k[1]["hash"]):
    hash = p["hash"]
    ct = p["ct"]
    path = p["path"]
    ext = p["ext"]
    if hash in known_hash:
        print(f"!!!!! file {file} is a copy of {known_hash[hash]}")
        print(f"{file} {ct}")
        print(f"{known_hash[hash]} {files[known_hash[hash]]['ct']}")
        # os.remove(file)
    else:
        known_hash[hash] = file
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