import os
import json
import urllib
import urllib2
from xml.etree import ElementTree

CONFIG_PATH = os.path.expanduser('~/Library/Application Support/CMi/plex.json')

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
    if not os.path.exists(CONFIG_PATH):
        return None
    with open(CONFIG_PATH) as f:
        return json.load(f)


def url(path, **params):
    c = config()
    params['X-Plex-Token'] = c['token']
    return '%s%s?%s' % (c['url'].rstrip('/'), path, urllib.urlencode(params))


def _open(path, **params):
    return urllib2.urlopen(urllib2.Request(url(path, **params), headers=HEADERS), timeout=10)


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


def report_progress(rating_key, seconds):
    _open('/:/progress', key=rating_key, identifier='com.plexapp.plugins.library', time=int(seconds) * 1000, state='playing')


def scrobble(rating_key):
    _open('/:/scrobble', key=rating_key, identifier='com.plexapp.plugins.library')


def is_watched(video):
    return int(video.get('viewCount', 0)) > 0
