"""
Show and episode metadata from TVmaze (https://www.tvmaze.com/api). Free and no API key needed.

Returns the same dict shapes the old TheTVDB client did, so callers don't need to care.
"""
import json
import re
from datetime import datetime
from urllib.parse import quote
from urllib.request import urlopen

BASE_URL = 'https://api.tvmaze.com'


def _get(path):
    return json.load(urlopen(BASE_URL + path, timeout=10))


def _strip_html(s):
    return re.sub(r'<[^>]+>', '', s or '').strip()


def _parse_date(s):
    return datetime.strptime(s, '%Y-%m-%d') if s else None


def get_series(series_name_search):
    """Return all possible matches for series_name_search, best match first"""
    return [
        dict(
            id=x['show']['id'],
            name=x['show']['name'],
            overview=_strip_html(x['show']['summary']),
            first_aired=_parse_date(x['show']['premiered']),
        )
        for x in _get('/search/shows?q=%s' % quote(series_name_search))
    ]


def get_series_all(series_id):
    """Return all episodes for a series"""
    return dict(episodes=[
        dict(
            id=x['id'],
            name=x['name'],
            season_number=x['season'],
            episode_number=x['number'],
            first_aired=_parse_date(x['airdate']),
            overview=_strip_html(x['summary']),
        )
        for x in _get('/shows/%s/episodes' % series_id)
    ])
