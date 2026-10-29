import os
import json
import uuid
import urllib.error
import urllib.parse
import urllib.request
from xml.etree import ElementTree
from django.conf import settings

PLEX_TV = 'https://plex.tv'


def _config_path():
    return os.path.join(settings.SUPPORT_FOLDER, 'plex.json')


def _load():
    if not os.path.exists(_config_path()):
        return {}
    with open(_config_path()) as f:
        return json.load(f)


def _save(c):
    with open(_config_path(), 'w') as f:
        json.dump(c, f, indent=4)


def config():
    """
    Reads plex.json from the CMi support folder, e.g.:
        {"url": "http://192.168.1.10:32400", "token": "abc123"}
    It's written when you sign in from the GUI, but you can also write it by hand.
    Returns None if Plex isn't configured.
    """
    c = _load()
    return c if c.get('url') and c.get('token') else None


def headers():
    c = _load()
    if 'client_id' not in c:
        # Plex identifies devices by this, so it needs to be unique per install and stay the same
        c['client_id'] = str(uuid.uuid4())
        _save(c)
    return {
        'X-Plex-Product': 'CMi',
        'X-Plex-Device-Name': 'CMi',
        'X-Plex-Client-Identifier': c['client_id'],
        'Accept': 'application/json',
    }


def _plex_tv(path, token=None, data=None):
    h = headers()
    if token:
        h['X-Plex-Token'] = token
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    return json.load(urllib.request.urlopen(urllib.request.Request(PLEX_TV + path, data=body, headers=h), timeout=10))


def create_pin():
    """Start a sign in. The user enters the returned code at plex.tv/link"""
    return _plex_tv('/api/v2/pins', data={'strong': 'false'})


def pin_token(pin_id):
    """The account token once the user has entered the code, otherwise None"""
    return _plex_tv('/api/v2/pins/%s' % pin_id).get('authToken')


def servers(account_token):
    return [x for x in _plex_tv('/api/v2/resources?includeHttps=1&includeRelay=1', token=account_token) if 'server' in x['provides'].split(',')]


def reachable_url(server):
    """The first connection to the server that answers: local first, then remote, then Plex's relay"""
    for connection in sorted(server['connections'], key=lambda x: (x['relay'], not x['local'])):
        try:
            urllib.request.urlopen(urllib.request.Request(connection['uri'] + '/identity', headers={'X-Plex-Token': server['accessToken']}), timeout=3)
            return connection['uri']
        except (urllib.error.URLError, OSError):
            pass
    return None


def sign_in(server):
    server_url = reachable_url(server)
    if server_url is None:
        return False
    c = _load()
    c.update(url=server_url, token=server['accessToken'], server_name=server['name'])
    _save(c)
    return True


def sign_out():
    c = _load()
    for key in ('url', 'token', 'server_name'):
        c.pop(key, None)
    _save(c)


def url(path, **params):
    c = config()
    params['X-Plex-Token'] = c['token']
    return '%s%s?%s' % (c['url'].rstrip('/'), path, urllib.parse.urlencode(params))


def _open(path, **params):
    h = headers()
    del h['Accept']  # the library endpoints are parsed as XML
    return urllib.request.urlopen(urllib.request.Request(url(path, **params), headers=h), timeout=10)


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
