import os
import signal
import requests
import time
import json
import hashlib
import redis
import logging
from logging import handlers
import sys
import traceback
import re
import shutil
import random
import string

# Define variables
YANDEX_DISK_PUBLIC_URL = None
LOCAL_SYNC_DIR = None
TEMP_DIR = None
TEMP_SUBDIR = '_temp'
MAX_RETRIES = 3  # Maximum attempts for downloading a file
KEYDB_HOST = '127.0.0.1'
KEYDB_PORT = 6379
HTTP_TIMEOUT = 10.0
MIN_TS = 1730000000
LOCAL_INDEX_NAME='index'
REMOTE_INDEX_NAME='remote_index'
MD5_INDEX_NAME='md5_index'

MAX_TIME_FROM_KEEPALIVE=600
MAX_TIME_FROM_START=7200
MIN_TIME_FROM_SYNC=500

LOG_LEVEL = logging.DEBUG
LOG_DIR = '/var/log/frame'


def eprint(*args, **kwargs):
    global logger
    print(*args, file=sys.stderr, **kwargs)
    if logger is not None:
        logger.error(*args)


def leave(rc=0):
    watchdog('stop')
    logger.info(f"Exiting with result code: {rc}")
    sys.exit(rc)


def init_logging(log_name='yd'):
    logger = logging.getLogger(log_name)
    logger.setLevel(LOG_LEVEL)

    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    try:
        if os.path.isdir(LOG_DIR):
            log_file = os.path.join(LOG_DIR, f'{log_name}.log')
            fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=10*1024*1024, backupCount=10)
        else:
            fh = logging.StreamHandler(sys.stdout)
        fh.setLevel(LOG_LEVEL)
        fh.setFormatter(formatter)
        logger.addHandler(fh)
    except Exception as ex:
        eprint(f"Exception occurred while setting up logger: {str(ex)}")
        #Без логов запускаться не будем
        sys.exit(-1)

    return logger


def connect_redis():
    redis_connection = None
    redis_host = os.environ.get('KEYDB_HOST', KEYDB_HOST)
    redis_port = int(os.environ.get('KEYDB_PORT', KEYDB_PORT))
    try:
       redis_connection = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    except Exception as e:
        eprint(f"Failed connecting to KeyDB at {redis_host}:{redis_port}: {traceback.format_exc()}")
        #Активное подключение к Redis/KeyDB критично для дальнейшей работы, без него - выходим
        leave(-1)
    return redis_connection


def load_config(config_path):
    global YANDEX_DISK_PUBLIC_URL
    if os.path.isfile(config_path):
        logger.debug(f"Loading config from {config_path}")
        with open(config_path) as file:
            for line in file:
                m=re.match(r'^\s*([a-zA-Z0-9\-_.]+)\s*=\s*\"?([a-zA-Z0-9\-_:./]+).*', line, flags=re.DOTALL | re.IGNORECASE)
                if m is not None:
                    logger.debug(f"Line: {m.group(1)}={m.group(2)}")
                    if m.group(1) == 'YANDEX_DISK_PUBLIC_URL' and re.match(r'https://disk.yandex.ru/d/[a-z0-9]+',
                                                                           m.group(2), flags=re.IGNORECASE):
                        YANDEX_DISK_PUBLIC_URL = m.group(2)
                        logger.info(f"Yandex disk public url found in config")


def notify_on_change(config_path):
    config_hash_path = str(config_path) + '.md5'
    if os.path.isfile(config_hash_path):
        logger.info(f'Removing config hash {config_hash_path} to notify on changes')
        os.unlink(config_hash_path)


# Calculate MD5 hash of a file
def calculate_md5(file_path, chunk_size=8192):
    md5 = hashlib.md5()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            md5.update(chunk)
    return md5.hexdigest()


def watchdog(status='keepalive'):
    pid = os.getpid()
    if status == 'start':
        r.hset('start_ts', pid, time.time())
        r.hset('keepalive_ts', pid, time.time())
    elif status == 'keepalive':
        r.hset('keepalive_ts', pid, time.time())
    elif status == 'sync':
        r.set('sync_ts', time.time())
    elif status == 'stop':
        r.hdel('start_ts', pid)
        r.hdel('keepalive_ts', pid)

    logger.info(f"Watchdog PID: {pid} status: {status}")


def check_process():
    #Проверяем, сколько прошло с последней синхронизации, чтобы избежать слишком частого обращения к API Яндекса

    last_sync_ts_str = r.get('sync_ts')
    if last_sync_ts_str is not None:
        try:
            last_sync_delta = time.time() - float(last_sync_ts_str)
            if last_sync_delta < MIN_TIME_FROM_SYNC:
                eprint(f"{last_sync_delta:.0f} sec. passed since last sync, min is {MIN_TIME_FROM_SYNC} sec")
                return False
        except ValueError:
            pass


    #Проверяем, есть ли другие активные процессы. Если есть - проверяем их состояние, при превышении порогов
    #общей продолжительности либо периода с последнего keepalive - такие процессы останавливаем.
    #Если после проверки других активных процессов не осталось - возвращаем True и разрешаем текущему экземпляру
    #запуститься. Если други активные и условно здоровые процессы есть - текущий процесс должен быть завершен
    cur_pid = os.getpid()
    active_count = 0
    for pid_str in r.hkeys('keepalive_ts'):
        pid = int(pid_str)
        if pid != cur_pid:
            process_start_ts = r.hget('start_ts', pid_str)
            process_running_time = None
            if process_start_ts is not None:
                try:
                    process_running_time = time.time() - float(process_start_ts)
                except ValueError:
                    process_running_time = None

            keepalive_ts = r.hget('keepalive_ts', pid_str)
            process_inactive_time = None
            if keepalive_ts is not None:
                try:
                    process_inactive_time = time.time() - float(keepalive_ts)
                except ValueError:
                    process_inactive_time = None

            logger.error(f"Process {pid} started {process_running_time:.1f} sec. ago, sent keepalive {process_inactive_time:.1f} sec. ago")

            if process_running_time is None or process_running_time > MAX_TIME_FROM_START or \
                process_inactive_time is None or process_inactive_time > MAX_TIME_FROM_KEEPALIVE:
                eprint(f"Process {pid} apparently stuck. Make it exit")
                try:
                    os.kill(pid, signal.SIGTERM)
                except Exception as e:
                    eprint(f"Failed to kill process {pid}: {str(e)}")

                r.hdel('start_ts', pid_str)
                r.hdel('keepalive_ts', pid_str)
            else:
                eprint(f"Another process {pid} is up and running. Leave it alone")
                active_count += 1

    return active_count == 0


# Function to download a file with integrity checks and retries
def download_file(download_url, local_file_path, remote_file_size, remote_md5):
    watchdog('keepalive')

    temp_file_path = os.path.join(TEMP_DIR, remote_md5)

    local_dir = os.path.dirname(local_file_path)
    logger.debug(f"Downloading {local_file_path} to {local_dir}")
    os.makedirs(local_dir, exist_ok=True)

    if not os.path.isdir(local_dir):
        eprint(f"Can't create folder {local_dir}")
        leave(-1)

    attempts = 0
    fatal = False

    while attempts < MAX_RETRIES and not fatal:
        try:

            local_copy = r.hget(MD5_INDEX_NAME, remote_md5)
            if local_copy is not None and os.path.isfile(local_copy):
                logger.info(f"Found local copy {local_copy} of the file {local_file_path}")
                shutil.copy(local_copy, temp_file_path)
            else:
                headers = {}
                if os.path.isfile(temp_file_path):
                    temp_file_size = os.path.getsize(temp_file_path)
                    if temp_file_size >= remote_file_size:
                        os.unlink(temp_file_path)
                        logger.error(f"Temporary file's broken as its size {temp_file_size} is already equal or larger than target's one {remote_file_size}")
                    else:
                        headers = {"Range": f"bytes={os.path.getsize(temp_file_path)}-"}
                with requests.get(download_url, headers=headers, stream=True, timeout=HTTP_TIMEOUT) as response:
                    response.raise_for_status()
                    with open(temp_file_path, 'ab') as f:
                        for chunk in response.iter_content(chunk_size=8192):
                            f.write(chunk)

            if os.path.getsize(temp_file_path) == remote_file_size:
                local_md5 = calculate_md5(temp_file_path)
                if local_md5 == remote_md5:
                    os.rename(temp_file_path, local_file_path)
                    logger.info(f"Downloaded and verified: {local_file_path} with MD5: {local_md5}")
                    return True
                else:
                    logger.error(f"MD5 mismatch for {local_file_path}. Retrying download from scratch, temp file will be removed")
                    os.unlink(temp_file_path)
            else:
                logger.error(f"File size mismatch for {local_file_path}. Retrying download.")
        except Exception as e:
            logger.error(f"exception name={type(e).__name__}, args={e.args}")
            logger.error(f"Exception occurred while getting {local_file_path}: {traceback.format_exc()}")
            if type(e).__name__ == 'ConnectionError':
                fatal = True
            else:
                sleep_for = 10 * 2 ** attempts
                logger.debug(f"Sleeping for {sleep_for:.1f} sec. before attempt N{attempts+2}")
                time.sleep(10 * 2 ** attempts)

        attempts += 1

    if os.path.exists(temp_file_path):
        os.remove(temp_file_path)
        logger.error(f"Failed to download {local_file_path} after {MAX_RETRIES} attempts. Removed incomplete file.")

    return False


def get_idx_rec(f, index_name=LOCAL_INDEX_NAME):
    try:
        idx_rec_str = r.hget(index_name, f)
        if idx_rec_str is not None:
            idx_rec = json.loads(idx_rec_str)
            return idx_rec
    except Exception as e:
        pass

    return None


def index_local_file(f, force=False, remove=False, size=None, md5=None):
    watchdog('keepalive')

    logger.debug(f"In index_local_file: {f=}, {force=}, {remove=}, {size=}, {md5=}")

    if remove:
        logger.debug(f"Removing {f} from the index")
        idx_rec = get_idx_rec(f)
        if idx_rec is not None:
            r.hdel(LOCAL_INDEX_NAME, f)
            r.hdel(MD5_INDEX_NAME, idx_rec['md5'])
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
                r.hset(LOCAL_INDEX_NAME, f, json.dumps(idx_rec))
                r.hset(MD5_INDEX_NAME, f_md5, f)
                logger.debug(f'set index({f}) = {idx_rec} ')
        else:
            logger.error(f"Can't add {f} to the index as it is not a file")


def check_local_file(f, size, md5):
    logger.debug(f"Check if file {f} exists and its size and md5 are equal {size} and {md5}")
    if f is not None and os.path.isfile(f):
        idx_rec = get_idx_rec(f, LOCAL_INDEX_NAME)
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
    watchdog('keepalive')

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


def purge_local_index(p):
    watchdog('keepalive')
    abs_path=os.path.abspath(p)
    for f in r.hkeys(LOCAL_INDEX_NAME):
        logger.debug(f'{f}')
        if abs_path in f and not os.path.isfile(f):
            logger.info(f'File {f} is not found within {p}, removing from the index')
            index_local_file(f, remove=True)


def index_remote_folder(public_url, path=None):
    watchdog('keepalive')

    global logger

    api_url = 'https://cloud-api.yandex.net/v1/disk/public/resources'
    limit = 100  # Number of items per request; adjust based on API limits
    offset = 0  # Starting point for the next batch

    while True:
        params = {
            'public_key': public_url,
            'fields': '_embedded.items.name,_embedded.items.md5,_embedded.items.size,_embedded.items.type,_embedded.items.mime_type,_embedded.items.path,_embedded.items.file',
            'limit': limit,
            'offset': offset
        }
        if path is not None:
            params['path'] = path

        try:
            response = requests.get(api_url, params=params, timeout=HTTP_TIMEOUT)
            response.raise_for_status()
            data = response.json()
            items = data.get('_embedded', {}).get('items', [])

            for item in items:
                path = item.get('path', '')
                item_type = item.get('type', '')
                if item_type == 'dir' and path != '':
                    index_remote_folder(public_url, path)  # Recurse into subdirectories
                elif item_type == 'file':
                    name = item.get('name', '')
                    mime = item.get('mime_type', '')
                    md5 = item.get('md5', '')
                    size = item.get('size', '')
                    download_url = item.get('file', '')
                    rel_path = re.sub(r'^/', '', path)
                    idx_rec = {'size': size, 'md5': md5, 'ts': time.time(), 'mime': mime, 'download_url': download_url}
                    r.hset(REMOTE_INDEX_NAME, rel_path, json.dumps(idx_rec))
                    logger.debug(f"Remote index: {rel_path} => {idx_rec}")

            # If fewer items than 'limit' are returned, we've fetched everything
            if len(items) < limit:
                logger.debug(f"Finished fetching remote folder {len(items)} < {limit}")
                break
            offset += limit  # Move to the next batch

        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching remote folder: {e}")
            break  # Exit on error to avoid infinite loop

def index_remote_folder_old(public_url, path=None):
    watchdog('keepalive')

    global logger

    api_url = 'https://cloud-api.yandex.net/v1/disk/public/resources'
    params = {'public_key': public_url, 'fields': '_embedded.items.name,_embedded.items.md5,_embedded.items.md5,' +\
        '_embedded.items.size,_embedded.items.type,_embedded.items.mime_type,_embedded.items.path,_embedded.items.file' }
    if path is not None:
        params['path'] = path

    response = requests.get(api_url, params=params, timeout=HTTP_TIMEOUT)
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
        #logger.debug(f"Item: {item}")
        if item.get('type','') == 'dir' and path != '':
            index_remote_folder(public_url, path)
        elif item_type == 'file':
            rel_path = re.sub(r'^/', '', str(path))
            idx_rec = {'size': size, 'md5': md5, 'ts': time.time(), 'mime': mime, 'download_url': download_url}
            r.hset(REMOTE_INDEX_NAME, rel_path, json.dumps(idx_rec))
            logger.debug(f"Remote index: {rel_path} => {idx_rec}")


def purge_remote_index(ts):
    watchdog('keepalive')

    if ts is not None and ts > MIN_TS:
        for f in r.hkeys(REMOTE_INDEX_NAME):
            idx_rec = get_idx_rec(f, REMOTE_INDEX_NAME)
            logger.debug(f"{f} => {idx_rec}")
            if idx_rec is not None and isinstance(idx_rec, dict):
                if 'ts' in idx_rec and idx_rec['ts'] != '':
                    rec_ts = float(idx_rec['ts'])
                    if rec_ts > MIN_TS and rec_ts < ts:
                        logger.info(f"Removing stale record {f} from the remote index {ts-rec_ts}")
                        r.hdel('remote_index', f)


def sync_remote_to_local_folder(target_folder, filter_mime=''):
    watchdog('keepalive')

    if not os.path.isdir(target_folder):
        eprint(f"Local target folder {target_folder} doesn't exist, abort syncing")
        leave(-1)

    download_list = list()
    delete_list = list()

    total_download_size = 0
    changed_files = 0

    for f in sorted(set(r.hkeys(REMOTE_INDEX_NAME)).union(
                   [re.sub(r'^/', '', local_f[len(target_folder):]) for local_f in r.hkeys(LOCAL_INDEX_NAME) if local_f.startswith(target_folder)])):
        local_f = os.path.join(target_folder, f)
        local_idx_rec = get_idx_rec(local_f, LOCAL_INDEX_NAME)
        remote_idx_rec = get_idx_rec(f, REMOTE_INDEX_NAME)
        logger.debug(f"Remote {f}: {remote_idx_rec}")
        logger.debug(f"Local {local_f}: {local_idx_rec}")
        if filter_mime != '' and remote_idx_rec is not None and \
                'mime' in remote_idx_rec and filter_mime not in remote_idx_rec['mime']:
            logger.debug(f"Mime filter {filter_mime} doesn't match file's type {remote_idx_rec['mime']}")
            continue

        if remote_idx_rec is not None:
            remote_idx_rec['local_f'] = local_f

        if local_idx_rec is not None:
            local_idx_rec['local_f'] = local_f

        if remote_idx_rec is not None and local_idx_rec is not None:
            if local_idx_rec.get('size', 'X') == remote_idx_rec.get('size', 'Y') and \
                    local_idx_rec.get('md5', 'X') == remote_idx_rec.get('md5', 'Y'):
                logger.info(f"LD == RD: {f}")
            else:
                logger.info(f"LD != RD: {f}")
                download_list.append(remote_idx_rec)
        elif remote_idx_rec is not None and local_idx_rec is None:
            logger.info(f"L_ != RD: {f}")
            total_download_size += remote_idx_rec.get('size', 0)
            download_list.append(remote_idx_rec)
        elif remote_idx_rec is None and local_idx_rec is not None:
            logger.info(f"LD != R_: {f}")
            delete_list.append(local_idx_rec)
        else:
            logger.error(f"L_ != R_: {f}")

    if len(download_list) > 0:
        du = shutil.disk_usage(target_folder)

        logger.info(f"There are {len(download_list)} files of total size {total_download_size / (1024 * 1024 * 1024):.3f}G on the Yandex Disk")
        logger.info(f"{target_folder} has {du.free / (1024 * 1024 * 1024):.3f}G available")

        if du.free > total_download_size:
            for idx_rec in download_list:
                watchdog('keepalive')
                logger.info(f"Download {idx_rec['local_f']}")
                if download_file(idx_rec['download_url'], idx_rec['local_f'], idx_rec['size'], idx_rec['md5']):
                    index_local_file(idx_rec['local_f'], size=idx_rec['size'], md5=idx_rec['md5'])
                    changed_files += 1
        else:
            logger.error(f"Downloading aborted due to lack of free space at {target_folder}")

    watchdog('keepalive')
    for idx_rec in delete_list:
        logger.info(f"Delete {idx_rec}")
        os.unlink(idx_rec['local_f'])
        index_local_file(idx_rec['local_f'], remove=True)
        changed_files += 1

    return changed_files


def delete_empty_folders(root):
    watchdog('keepalive')

    deleted = set()

    for current_dir, subdirs, files in os.walk(root, topdown=False):
        #logger.debug(f"{current_dir=} {subdirs=} files_cnt={len(files)}")
        still_has_subdirs = False
        for subdir in subdirs:
            if os.path.join(current_dir, subdir) not in deleted:
                still_has_subdirs = True
                #logger.debug(f"{current_dir=} still has subdirs: {subdir}")
                break

        if not any(files) and not still_has_subdirs and TEMP_SUBDIR not in current_dir:
            logger.debug(f"Delete empty dir {current_dir}")
            os.rmdir(current_dir)
            deleted.add(current_dir)

    return deleted


start_ts = time.time()

logger = init_logging()
r = connect_redis()


#r.flushdb()


if len(sys.argv) < 3:
    eprint(f"Usage: {sys.argv[0]} path_to_frame.cfg path_to_images_folder")
    leave(-1)

config_file=os.path.expanduser(sys.argv[1])
if not os.path.isfile(config_file):
    eprint(f"config file {config_file} doesn't exist")
    leave(-1)

LOCAL_SYNC_DIR=os.path.expanduser(sys.argv[2])
if not os.path.isdir(LOCAL_SYNC_DIR):
    os.makedirs(LOCAL_SYNC_DIR, exist_ok=True)

if not os.path.isdir(LOCAL_SYNC_DIR):
    eprint(f"sync dir {LOCAL_SYNC_DIR} doesn't exist and can't be created")
    leave(-1)

load_config(config_file)

#Probe sync dir if it is open for writing
if LOCAL_SYNC_DIR is None or not os.path.isdir(LOCAL_SYNC_DIR) or not os.access(LOCAL_SYNC_DIR, os.W_OK):
    eprint(f"Local sync dir {LOCAL_SYNC_DIR} doesn't exist or isn't writable")
    leave(-1)

TEMP_DIR = os.path.join(LOCAL_SYNC_DIR, TEMP_SUBDIR)
os.makedirs(TEMP_DIR, exist_ok=True)
if not os.path.isdir(TEMP_DIR) or not os.access(TEMP_DIR, os.W_OK):
    eprint(f"Temp dir {TEMP_DIR} doesn't exist or isn't writable")
    leave(-1)
    #letters = string.ascii_lowercase
    #random_name = ''.join(random.choice(letters) for i in range(16))

if check_process():
    logger.info('Checks completed, execution permitted')
else:
    eprint('Not all conditions met to run the sync, leaving')
    leave(-1)

watchdog('start')

logger.info(f"Starting sync to folder {LOCAL_SYNC_DIR} with temp dir {TEMP_DIR}")

index_local_folder(LOCAL_SYNC_DIR)

purge_local_index(LOCAL_SYNC_DIR)

index_remote_folder(YANDEX_DISK_PUBLIC_URL)

purge_remote_index(start_ts)

#Фиксируем, на какой момент синхронизированы данные
watchdog('sync')

changes = sync_remote_to_local_folder(LOCAL_SYNC_DIR, filter_mime='image')
if changes > 0:
    notify_on_change(config_file)

delete_empty_folders(LOCAL_SYNC_DIR)

watchdog('stop')

#ToDo: По окончании результативной синхронизации (когда были скачаны или удалены файлы) перезапускать слайдшоу
#ToDo: Ограничение на общее количество попыток обращений к Я.Д
#ToDo: Уведомление через телеграм об ошибках




