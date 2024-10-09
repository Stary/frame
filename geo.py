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
        delta_ms = 0.0

    logger.debug(f"{last_ts=} {time.time()=:.6f} {delta_ms=:.6f} {ms=:.6f} {left_ms=:.6f}")

    if left_ms > 0:
        logger.debug(f"sleeping for {left_ms:.2f} ms")
        time.sleep(left_ms*0.001)

    r.set('last_delay_ts', time.time())


def get_nominatim_data(lat, lon):
    global r
    global logger
    language = 'ru'
    zoom = 18
    lat_str = f"{lat:.6f}"
    lon_str = f"{lon:.6f}"
    key=f"({lat_str},{lon_str},{zoom},{language})"
    logger.debug(f"in get_nominatim_data({lat_str},{lon_str})")

    data = None
    try:
        data_str = r.hget('nominatim_cache', key)
        if data_str is not None:
            data = json.loads(data_str)
            logger.debug(f"Found in L1 cache: {data_str} at ({lat_str},{lon_str})")
        else:
            url = f'https://nominatim.openstreetmap.org/reverse?lat={lat_str}&lon={lon_str}&format=json&accept-language={language}&zoom={zoom}'
            logger.debug(f"{url=}")
            headers = {'User-Agent': 'Photo Frame v.1.0'}
            throttle(1500)
            req_res = requests.get(url=url, headers=headers)
            status_code = req_res.status_code
            if status_code == 200:
                data = req_res.json()
                if data is not None and r is not None:
                    logger.info(f"Save to L1 cache: {data} at ({lat_str},{lon_str})")
                    r.hset('nominatim_cache', key, json.dumps(data))
            else:
                eprint("Error {req_res}")
    except Exception as e:
        logger.error(f"Exception: {repr(e)}")

    return data


def get_descr_by_address(address):
    descr = ''
    addr = []

    logger.debug(f"{address=}")

    if 'country_code' in address and 'country' in address and address['country_code'] != 'ru':
        addr.append(address['country'])

    for p in ['village', 'town', 'locality', 'municipality', 'county', 'state', 'city']:
        if p in address:
            addr.append(address[p])
            break

    for p in ['neighbourhood', 'residential', 'square', 'tourism', 'historic', 'shop', 'amenity']:
        if p in address:
            addr.append(address[p])

    if len(addr) > 0:
        descr = ', '.join(addr)

    logger.debug(f"{descr=}")

    return descr


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
            logger.error(f"Exception: {traceback.format_exc()}")


def get_place_descr(lat, lon):
    global r
    global logger

    logger.info(f">>>>>>> in get_place_descr({lat:.6f},{lon:.6f})")

    if r is None:
        return 'KeyDB ERROR'

    place_descr = ''
    address = dict()

    #Шаг 1 - поиск ближайшей области, заданной пользователем, в радиус которой попадает точка
    try:
        #Для совместимости реализован вызов двух вариантов методов модуля redis
        #версию модуля определяем по наличию метода geosearch
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
            user_places = r.georadius('user_places', lon, lat, 1000, 'km', withdist=True, sort='ASC')

        if len(user_places) > 0:
            logger.debug(f"{user_places=}")

            for pr, dist in user_places:
                descr, radius_str = pr.split('|')
                try:
                    radius = float(radius_str)
                except Exception as e:
                    radius = 10.0

                if dist < radius:
                    place_descr = descr
                    logger.info(f"User defined area '{descr}' with radius {radius:.2f} found in {dist:.2f} km")
                    break
                else:
                    logger.debug(f"User defined area '{descr}' with radius {radius:.2f} is too far ({dist:.2f} km)")

    except Exception as e:
        logger.error(f"Exception: {traceback.format_exc()}")


    #Шаг 2 - ищем в кэше Nominatim второго уровня (координаты округляются до 100м)
    #(первый уровень блокирует повторные запросы к сервису с точно совпадающими координатами, без округления)
    try:
        if place_descr is None or place_descr == '':
            if hasattr(r, 'geosearch'):
                cached_res = r.geosearch(
                    name='nominatim_address',
                    longitude=lon,
                    latitude=lat,
                    radius=50,
                    unit='m',
                    withdist=True,
                    sort='ASC')
            else:
                cached_res = r.georadius('nominatim_address', lon, lat, 50, 'm', withdist=True, sort='ASC')

            if cached_res is not None and len(cached_res) > 0:
                logger.info(f"Found in L2 cache: {cached_res}")
                address = json.loads(cached_res[0][0])
                place_descr = get_descr_by_address(address)

    except Exception as e:
        logger.error(f"Exception: {traceback.format_exc()}")

    #Шаг 3 - поиск по точным координатам в сервисе Nominatim
    try:
        if place_descr is None or place_descr == '':
            nominatim_data = get_nominatim_data(lat, lon)
            logger.debug(nominatim_data)
            if nominatim_data is not None and isinstance(nominatim_data, dict):
                if 'address' in nominatim_data:
                    address = nominatim_data['address']

                    if len(address) > 0:
                        place_descr = get_descr_by_address(address)
                        try:
                            address_json = json.dumps(address, indent=4, sort_keys=True, ensure_ascii=False)
                            if hasattr(r, 'geosearch'):
                                r.geoadd('nominatim_address', [lon, lat, address_json])
                            else:
                                r.geoadd('nominatim_address', lon, lat, address_json)
                            logger.info(f"Save to L2 cache: {address_json} at ({lat:.6f},{lon:.6f})")
                        except Exception as e:
                            logger.error(f"Exception: {traceback.format_exc()}")

    except Exception as e:
        logger.error(f"Exception: {traceback.format_exc()}")

    logger.info(f"<<<<<< ({lat:.6f},{lon:.6f}) => {place_descr}")
    return place_descr



LOG_LEVEL = logging.DEBUG
LOG_DIR = '/var/log/frame'

if __name__ == '__main__':
    os.environ['REDIS_HOST'] = '192.168.1.123'

logger = init_logging()
r = connect_redis()

if __name__ == '__main__':
    for p in [[55.756098, 37.638963]]: #, [59.855159, 30.350305], [59.423, 30.3459], [48.853, 2.294572], [59.992, 31.03]]:
        #print(get_nominatim_data(p[0], p[1]))
        print(get_place_descr(p[0], p[1]))



