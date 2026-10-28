import subprocess
from math import ceil
from django.http import HttpResponse, HttpResponseRedirect
from django.shortcuts import render
from CMi.utils import ListItem, title_sort_key
from CMi.plex import client


def to_columns(items, height=11):
    width = int(ceil(len(items) / float(height)))
    rows = [[None for _ in xrange(width)] for _ in xrange(height)]
    for i, item in enumerate(items):
        rows[i % height][i / height] = item
    return rows


def index(request):
    items = [ListItem('/plex/section/%s' % x.get('key'), x.get('title')) for x in client.sections()]
    return render(request, 'list.html', {'title': 'Plex', 'items': items})


def section(request, section_id):
    items = []
    for x in client.section_items(section_id):
        if x.tag == 'Directory' and x.get('type') == 'show':
            unwatched = int(x.get('leafCount', 0)) - int(x.get('viewedLeafCount', 0))
            if unwatched:
                items.append(ListItem('/plex/show/%s' % x.get('ratingKey'), x.get('title'), unwatched))
        elif x.tag == 'Video' and not client.is_watched(x):
            items.append(ListItem('/plex/%s' % x.get('ratingKey'), x.get('title'), x.get('year')))
    items.sort(key=lambda x: title_sort_key(x.title))
    return render(request, 'list.html', {'title': 'Plex', 'rows': to_columns(items)})


class Episode(object):
    def __init__(self, video):
        self.url = '/plex/%s/' % video.get('ratingKey')
        self.name = video.get('title')
        self.season = int(video.get('parentIndex', 0))
        self.episode = video.get('index', '')
        self.aired = video.get('originallyAvailableAt', '')
        self.watched = client.is_watched(video)
        self.in_progress = int(video.get('viewOffset', 0)) > 0


def show(request, show_id):
    videos = client.episodes(show_id)
    if not videos:
        return HttpResponse(':back')
    eps = [Episode(x) for x in videos]
    # Continue an episode in progress, otherwise the first unwatched one
    next_episode = next((e for e in eps if e.in_progress and not e.watched), None) or next((e for e in eps if not e.watched), None)
    if next_episode is eps[0]:
        next_episode = None

    seasons = sorted({e.season for e in eps})
    columns = [[e for e in eps if e.season == season] for season in seasons]
    height = max(len(c) for c in columns)
    rows = [[c[i] if i < len(c) else None for c in columns] for i in xrange(height)]
    return render(request, 'plex/show.html', {
        'title': videos[0].get('grandparentTitle'),
        'rows': rows,
        'next_episode': next_episode,
        'seasons': seasons,
    })


def play(request, rating_key):
    seconds = int(client.metadata(rating_key).get('viewOffset', 0)) / 1000
    # Plex needs the token as a query parameter, but CMiVideoPlayer treats the query string as its own
    # parameters, so we give it a local URL that redirects to the real stream instead.
    subprocess.call(['open', 'CMiVideoPlayer://http://127.0.0.1:19817/plex/%s/stream?seconds=%s&callback=plex/%s' % (rating_key, seconds, rating_key)])
    return HttpResponse(':back')


def stream(request, rating_key):
    return HttpResponseRedirect(client.part_url(rating_key))


def ended(request, rating_key):
    client.scrobble(rating_key)
    return HttpResponse(':nothing')


def position(request, rating_key, position):
    client.report_progress(rating_key, position)
    return HttpResponse(':nothing')
