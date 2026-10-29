import os
import json
import urllib.parse
import urllib.request
from xml.etree import ElementTree
from django.conf import settings

HEADERS = {
    'X-Plex-Product': 'CMi',
    'X-Plex-Client-Identifier': 'cmi-media-center',
}


def config():
    """
    Reads plex.json from the CMi support folder, e.g.:
        {"url": "http://192.168.1.10:32400", "token": "abc123"}
    Returns None if Plex isn't configured.
    """
    config_path = os.path.join(settings.SUPPORT_FOLDER, 'plex.json')
    if not os.path.exists(config_path):
        return None
    with open(config_path) as f:
        return json.load(f)


def url(path, **params):
    c = config()
    params['X-Plex-Token'] = c['token']
    return '%s%s?%s' % (c['url'].rstrip('/'), path, urllib.parse.urlencode(params))


def _open(path, **params):
    return urllib.request.urlopen(urllib.request.Request(url(path, **params), headers=HEADERS), timeout=10)


def get(path, **params):
    return ElementTree.parse(_open(path, **params)).getroot()


def sections():
    return [x for x in get('/library/sections').findall('Directory') if x.get('type') in ('movie', 'show')]


def section_items(section_id):
    return list(get('/library/sections/%s/all' % section_id))


def episodes(show_id):
    return get('/library/metadata/%s/allLeaves' % show_id).findall('Video')


def metadata(rating_key):
    return get('/library/metadata/%s' % rating_key).find('Video')


def part_url(rating_key):
    return url(metadata(rating_key).find('Media/Part').get('key'))


def report_progress(rating_key, milliseconds):
    _open('/:/progress', key=rating_key, identifier='com.plexapp.plugins.library', time=int(milliseconds), state='playing')


def scrobble(rating_key):
    _open('/:/scrobble', key=rating_key, identifier='com.plexapp.plugins.library')


def is_watched(video):
    return int(video.get('viewCount', 0)) > 0
