import traceback
import redis
import subprocess
import sys
import os
import re
import requests
import time
import json
import logging
from logging import handlers


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def init_logging():
    logger = logging.getLogger('geo')
    logger.setLevel(LOG_LEVEL)

    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    log_file = os.path.join(LOG_DIR if os.path.isdir(LOG_DIR) else '.', 'geo.log')
    try:
        fh = logging.handlers.RotatingFileHandler(log_file)
        fh.setLevel(LOG_LEVEL)
        fh.setFormatter(formatter)
        logger.addHandler(fh)
    except Exception as ex:
        eprint(f"Exception occured while opening log file {log_file}: {str(ex)}")

    return logger


def connect_redis():
    redis_connection = None
    try:
        redis_host = os.environ.get('REDIS_HOST', '127.0.0.1')
        redis_port = int(os.environ.get('REDIS_PORT', 6379))
        redis_connection = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    except Exception as e:
        eprint(f"Exception: {traceback.format_exc()}")
    return redis_connection


def throttle(ms):
    global r
    global logger
    last_ts = r.get('last_delay_ts')
    if last_ts is not None:
        delta_ms = (time.time() - float(last_ts)) * 1000
        left_ms = ms - delta_ms
    else:
        left_ms = ms

    logger.debug(f"{last_ts=} {time.time()=:.6f} {delta_ms=:.6f} {ms=:.6f} {left_ms=:.6f}")

    if left_ms > 0:
        logger.debug(f"sleeping for {left_ms:.2f} ms")
        time.sleep(left_ms*0.001)

    r.set('last_delay_ts', time.time())


def get_nominatim_data(lat, lon):
    global r
    global logger
    language = 'ru'
    zoom = 15
    lat_str = f"{lat:.6f}"
    lon_str = f"{lon:.6f}"
    key=f"({lat_str},{lon_str},{zoom},{language})"
    logger.debug(f"in get_nominatim_data({lat_str},{lon_str})")

    data = None
    try:
        data_str = r.hget('nominatim_cache', key)
        if data_str is not None:
            data = json.loads(data_str)
            logger.debug(f"cached: {data_str}")
        else:
            url = f'https://nominatim.openstreetmap.org/reverse?lat={lat_str}&lon={lon_str}&format=json&accept-language={language}&zoom={zoom}'
            headers = {'User-Agent': 'Photo Frame v.1.0'}
            throttle(1500)
            req_res = requests.get(url=url, headers=headers)
            status_code = req_res.status_code
            if status_code == 200:
                data = req_res.json()
                logger.info(f"nominatim: {data}")
                if data is not None and r is not None:
                    r.hset('nominatim_cache', key, json.dumps(data))
            else:
                eprint("Error {req_res}")
    except Exception as e:
        logger.error(f"Exception: {repr(e)}")

    return data


def set_place_descr(lat, lon, descr, radius = 100.0):
    global r
    global logger
    if r is not None:
        try:
            name = f"{descr}|{radius:.2f}"
            if hasattr(r, 'geosearch'):
                r.geoadd('user_places', [lon, lat, name])
            else:
                r.geoadd('user_places', lon, lat, name)
            logger.info(f"Added point {descr} at ({lat:.6f},{lon:.6f}) with radius {radius:.2f}")
        except Exception as e:
            eprint(f"Exception: {traceback.format_exc()}")



LOG_LEVEL = logging.DEBUG
LOG_DIR = '/var/log/frame'


os.environ['REDIS_HOST'] = '192.168.1.123'

logger = init_logging()
r = connect_redis()


for p in [[59.442, 30.3459], [48.852, 2.294572], [59.991, 31.03]]:
    print(get_nominatim_data(p[0], p[1]))



