"""
Title search using IMDb's search suggestion endpoint. No API key needed.

Returns the same dict shape as IMDbPY's search_movie() did, so callers don't need to care.
"""
import json
from urllib.parse import quote
from urllib.request import urlopen


def search_movie(title):
    """Return titles (movies, but also series etc, like IMDbPY did) matching title, best match first"""
    data = json.load(urlopen('https://v3.sg.media-imdb.com/suggestion/x/%s.json' % quote(title.lower()), timeout=10))
    return [
        dict(title=x['l'], year=x['y'], kind=x['qid'], imdb_id=x['id']) if 'y' in x else dict(title=x['l'], kind=x['qid'], imdb_id=x['id'])
        for x in data.get('d', [])
        if 'qid' in x  # people don't have a qid
    ]
