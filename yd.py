import os
import requests
import time
import json
import hashlib
import redis
from urllib.parse import urljoin
import logging
from logging import handlers
import sys
import traceback
import re
import random
import string

from pyasn1_modules.rfc2985 import pkcs_9_at_challengePassword

# Define variables
YANDEX_DISK_PUBLIC_URL = None
LOCAL_SYNC_DIR = None
TEMP_DIR = None
TEMP_SUBDIR = '_temp'
REMOVE_PATTERN = '__remove__'
SYNC_INTERVAL = 300  # Sync every 5 minutes (in seconds)
MAX_RETRIES = 3  # Maximum attempts for downloading a file
KEYDB_HOST = '127.0.0.1'
KEYDB_PORT = 6379

LOG_LEVEL = logging.DEBUG
LOG_DIR = '/var/log/frame'

# Ensure sync directories exist
#os.makedirs(LOCAL_SYNC_DIR, exist_ok=True)
#os.makedirs(TEMP_DIR, exist_ok=True)

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def init_logging(log_name='yd'):
    logger = logging.getLogger(log_name)
    logger.setLevel(LOG_LEVEL)

    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    log_file = os.path.join(LOG_DIR if os.path.isdir(LOG_DIR) else '.', f'{log_name}.log')
    try:
        if __name__ == '__main__':
            pass
            fh = logging.StreamHandler(sys.stdout)
        else:
            fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=10*1024*1024, backupCount=10)
        fh.setLevel(LOG_LEVEL)
        fh.setFormatter(formatter)
        logger.addHandler(fh)
    except Exception as ex:
        eprint(f"Exception occured while opening log file {log_file}: {str(ex)}")
        #Без логов запускаться не будем
        sys.exit(-1)

    return logger


def connect_redis():
    redis_connection = None
    try:
        redis_host = os.environ.get('REDIS_HOST', '127.0.0.1')
        redis_port = int(os.environ.get('REDIS_PORT', 6379))
        redis_connection = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    except Exception as e:
        eprint(f"Exception: {traceback.format_exc()}")
        #Активное подключение к Redis/KeyDB критичны для дальнейшей работы, без него - выходим
        sys.exit(-1)
    return redis_connection


def load_config(config_path):
    global YANDEX_DISK_PUBLIC_URL
    if os.path.isfile(config_path):
        logger.debug(f"Loading config from {config_path}")
        with open(config_path) as file:
            for line in file:
                m=re.match(r'^\s*([a-zA-Z0-9\-_.]+)\s*=\s*([a-zA-Z0-9\-_:./]+).*', line, flags=re.DOTALL | re.IGNORECASE)
                if m is not None:
                    logger.debug(f"Line: {m.group(1)}={m.group(2)}")
                    if m.group(1) == 'YANDEX_DISK_PUBLIC_URL' and re.match(r'https://disk.yandex.ru/d/[a-z0-9]+',
                                                                           m.group(2), flags=re.IGNORECASE):
                        YANDEX_DISK_PUBLIC_URL = m.group(2)
                        logger.info(f"Yandex disk public url found in config")

# Calculate MD5 hash of a file
def calculate_md5(file_path, chunk_size=8192):
    md5 = hashlib.md5()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            md5.update(chunk)
    return md5.hexdigest()


# Function to download a file with integrity checks and retries
def download_file(download_url, local_file_path, remote_file_size, remote_md5):
    temp_file_path = os.path.join(TEMP_DIR, remote_md5)

    attempts = 0
    while attempts < MAX_RETRIES:
        headers = {"Range": f"bytes={os.path.getsize(temp_file_path)}-"} if os.path.exists(temp_file_path) else {}
        with requests.get(download_url, headers=headers, stream=True) as response:
            response.raise_for_status()
            with open(temp_file_path, 'ab') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)

        if os.path.getsize(temp_file_path) == remote_file_size:
            local_md5 = calculate_md5(temp_file_path)
            if local_md5 == remote_md5:
                os.rename(temp_file_path, local_file_path)
                logger.info(f"Downloaded and verified: {local_file_path} with MD5: {local_md5}")
                return
            else:
                logger.error(f"MD5 mismatch for {local_file_path}. Retrying download.")
        else:
            logger.error(f"File size mismatch for {local_file_path}. Retrying download.")

        attempts += 1

    if os.path.exists(temp_file_path):
        os.remove(temp_file_path)
        logger.error(f"Failed to download {local_file_path} after {MAX_RETRIES} attempts. Removed incomplete file.")


def get_idx_rec(f):
    idx_rec_str = r.hget('index', f)
    if idx_rec_str is not None:
        idx_rec = json.loads(idx_rec_str)
        return idx_rec
    else:
        return None


def index_local_file(f, force=False, remove=False, size=None, md5=None):
    logger.debug(f"In index_local_file: {f=}, {force=}, {remove=}, {size=}, {md5=}")
    if remove:
        logger.debug(f"Removing {f} from the index")
        r.hdel('index', f)
    else:
        if os.path.isfile(f):
            logger.debug(f"Adding {f} to the index")
            file_stats = os.stat(f)
            f_mtime = file_stats.st_mtime
            f_size = file_stats.st_size
            idx_mtime = None
            idx_size = None
            idx_md5 = None

            logger.debug(f"{f=} {file_stats=}")

            if size is not None and size != f_size:
                logger.error(f"File {f} remote size {size} is not equal to local {f_size}")

                idx_rec = get_idx_rec(f)

                if idx_rec is not None and isinstance(idx_rec, dict):
                    idx_mtime = idx_rec.get('mtime', None)
                    idx_size = idx_rec.get('size', None)
                    idx_md5 = idx_rec.get('md5', None)
                    logger.debug(f'get index({f}) = {idx_rec}')

            if idx_mtime is None or idx_size is None or idx_md5 is None or \
                idx_mtime != f_mtime or idx_size != f_size or force:
                f_md5 = md5 if md5 is not None else calculate_md5(f)
                idx_rec = {'mtime': f_mtime, 'size': f_size, 'md5': f_md5, 'ts': time.time()}
                r.hset('index', f, json.dumps(idx_rec))
                logger.debug(f'set index({f}) = {idx_rec} ')
        else:
            logger.error(f"Can't add {f} to the index as it is not a file")


def check_local_file(f, size, md5):
    logger.debug(f"Check if file {f} exists and its size and md5 are equal {size} and {md5}")
    if f is not None and os.path.isfile(f):
        idx_rec = get_idx_rec(f)
        if idx_rec is not None and isinstance(idx_rec, dict):
            #idx_mtime = idx_rec.get('mtime', None)
            idx_size = idx_rec.get('size', None)
            idx_md5 = idx_rec.get('md5', None)
            if idx_size is not None and idx_md5 is not None and idx_size == size and idx_md5 == md5:
                return True
            else:
                logger.debug(f"{size=} {idx_size=} {md5=} {idx_md5=}")
    return False


def index_local_folder(p):
    abs_path=os.path.abspath(p)
    if os.path.isfile(abs_path):
        logger.debug(f"Indexing file {abs_path}")
        index_local_file(abs_path)
    elif os.path.isdir(abs_path):
        logger.debug(f"Indexing dir  {abs_path}")
        for f in os.listdir(abs_path):
            index_local_folder(os.path.join(abs_path,f))
    else:
        logger.debug(f"Unknown type: {abs_path}")
        #Unknown type
        pass

def purge_local_folder_index(p):
    abs_path=os.path.abspath(p)
    for f in r.hkeys('index'):
        logger.debug(f'{f}')
        if abs_path in f and not os.path.isfile(f):
            logger.info(f'File {f} is not found within {p}, removing from the index')
            index_local_file(f, remove=True)


def sync_remote_folder_to_local(public_url, target_folder, path=None, filter_mime=None):
    global logger
    if not os.path.isdir(target_folder):
        logger.error(f"Target folder {target_folder} doesn't exist, can't sync")
        return
    else:
        target_folder = os.path.abspath(target_folder)
        logger.info(f"Sync target base is {target_folder}")

    api_url = 'https://cloud-api.yandex.net/v1/disk/public/resources'
    params = {'public_key': public_url, 'fields': '_embedded.items.name,_embedded.items.md5,_embedded.items.md5,' +\
        '_embedded.items.size,_embedded.items.type,_embedded.items.mime_type,_embedded.items.path,_embedded.items.file' }
    if path is not None:
        #path фактически 0 относительный путь, хотя начинается с /, исправим это
        target_subfolder = os.path.join(target_folder, re.sub('^/','',path))
        logger.debug(f"join: {target_folder=} + {path=} => {target_subfolder=}")
        params['path'] = path
    else:
        target_subfolder = target_folder
    logger.debug(f"Syncing remote dir {path} to {target_subfolder}")

    response = requests.get(api_url, params=params)
    response.raise_for_status()
    #logger.debug(f"{json.dumps(response.json(), indent=4, sort_keys=True, ensure_ascii=False)}")

    items = response.json().get('_embedded', {}).get('items', [])
    for item in items:
        name = item.get('name', '')
        path = item.get('path', '')
        mime = item.get('mime_type', '')
        md5 = item.get('md5', '')
        size = item.get('size', '')
        item_type = item.get('type', '')
        download_url = item.get('file', '')
        logger.debug(f"Item: {item}")
        if item.get('type','') == 'dir' and path != '':
            sync_remote_folder_to_local(public_url, target_folder, path)
        elif item_type == 'file' and (filter_mime is None or mime=='' or filter_mime in mime):
            target_file = os.path.join(target_subfolder, name)
            if REMOVE_PATTERN in name:
                name2 = name.replace(REMOVE_PATTERN, '')
                target_file = os.path.join(target_subfolder, name2)
                logger.info(f"File {target_file} marked for deletion")
                if os.path.isfile(target_file):
                    logger.info(f"Deleting {target_file} from the disk and from the index")
                    os.unlink(target_file)
                    index_local_file(target_file, remove=True)
                else:
                    logger.debug(f"File {target_file} doesn't exist")
            elif check_local_file(target_file, size, md5):
                logger.debug(f"File {target_file} has already been downloaded, verified and indexed")
            else:
                logger.debug(f"Process file {target_file}")
                os.makedirs(target_subfolder, exist_ok=True)
                download_file(download_url, target_file, size, md5)
                index_local_file(target_file, size=size, md5=md5)


logger = init_logging()
r = connect_redis()

#r.flushdb()

logger.debug(f"{len(sys.argv)} {sys.argv}")

if len(sys.argv) < 3:
    eprint(f"Usage: {sys.argv[0]} path_to_frame.cfg path_to_images_folder")
    sys.exit(-1)

config_file=os.path.expanduser(sys.argv[1])
if not os.path.isfile(config_file):
    eprint(f"config file {config_file} doesn't exist")
    sys.exit(-1)

LOCAL_SYNC_DIR=os.path.expanduser(sys.argv[2])
if not os.path.isdir(LOCAL_SYNC_DIR):
    eprint(f"sync dir {LOCAL_SYNC_DIR} doesn't exist")
    sys.exit(-1)

load_config(config_file)

#Probe sync dir if it is open for writing
if LOCAL_SYNC_DIR is None or not os.path.isdir(LOCAL_SYNC_DIR) or not os.access(LOCAL_SYNC_DIR, os.W_OK):
    eprint(f"Local sync dir {LOCAL_SYNC_DIR} doesn't exist or isn't writable")
    sys.exit(-1)

TEMP_DIR = os.path.join(LOCAL_SYNC_DIR, TEMP_SUBDIR)
os.makedirs(TEMP_DIR, exist_ok=True)
if not os.path.isdir(TEMP_DIR) or not os.access(TEMP_DIR, os.W_OK):
    eprint(f"Temp dir {TEMP_DIR} doesn't exist or isn't writable")
    sys.exit(-1)
    #letters = string.ascii_lowercase
    #random_name = ''.join(random.choice(letters) for i in range(16))


logger.info(f"Starting sync to folder {LOCAL_SYNC_DIR} with temp dir {TEMP_DIR}")

index_local_folder(LOCAL_SYNC_DIR)

purge_local_folder_index(LOCAL_SYNC_DIR)

sync_remote_folder_to_local(YANDEX_DISK_PUBLIC_URL, LOCAL_SYNC_DIR, filter_mime='image/')
