import subprocess
import time
import urllib.error
from math import ceil
from django.http import HttpResponse, HttpResponseRedirect
from django.shortcuts import render
from CMi.utils import ListItem, title_sort_key
from CMi.plex import client


def to_columns(items, height=11):
    width = int(ceil(len(items) / float(height)))
    rows = [[None for _ in range(width)] for _ in range(height)]
    for i, item in enumerate(items):
        rows[i % height][i // height] = item
    return rows


# Sign in state. There is only one CMi user, so keeping it in the process is fine.
_pin = None  # the code currently shown on screen
_account_token = None  # signed in to plex.tv, but not yet chosen a server
PIN_LIFETIME = 14 * 60  # plex.tv expires them after 15 minutes


def index(request):
    global _pin
    c = client.config()
    if c:
        items = [ListItem('/plex/section/%s' % x.get('key'), x.get('title')) for x in client.sections()]
        items.append(ListItem('/plex/sign_out', 'Sign out', c.get('server_name')))
        return render(request, 'list.html', {'title': 'Plex', 'items': items})

    if _account_token:
        items = [ListItem('/plex/server/%s' % x['clientIdentifier'], x['name'], '' if x['owned'] else 'shared') for x in client.servers(_account_token)]
        return render(request, 'list.html', {'title': 'Choose Plex server' if items else 'No Plex servers found', 'items': items})

    if _pin is None or time.time() - _pin['created'] > PIN_LIFETIME:
        _pin = client.create_pin()
        _pin['created'] = time.time()
    return render(request, 'plex/sign_in.html', {'code': _pin['code']})


def sign_in_check(request):
    """Polled by the sign in page. :refresh makes it reload, showing the libraries or the server list"""
    global _pin, _account_token
    if _pin is None:
        return HttpResponse(':refresh')
    if time.time() - _pin['created'] > PIN_LIFETIME:
        return HttpResponse(':refresh')  # index makes a new code
    try:
        token = client.pin_token(_pin['id'])
    except urllib.error.HTTPError:
        _pin = None  # expired or unknown
        return HttpResponse(':refresh')
    if not token:
        return HttpResponse(':nothing')
    _pin = None
    servers = client.servers(token)
    if len(servers) != 1 or not client.sign_in(servers[0]):
        _account_token = token
    return HttpResponse(':refresh')


def choose_server(request, client_identifier):
    global _account_token
    if _account_token is None:
        return HttpResponse(':back')
    for server in client.servers(_account_token):
        if server['clientIdentifier'] == client_identifier:
            if client.sign_in(server):
                _account_token = None
            else:
                print('Could not connect to Plex server', server['name'])
    return HttpResponse(':back')


def sign_out(request):
    client.sign_out()
    return HttpResponse(':back')


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
    rows = [[c[i] if i < len(c) else None for c in columns] for i in range(height)]
    return render(request, 'plex/show.html', {
        'title': videos[0].get('grandparentTitle'),
        'rows': rows,
        'next_episode': next_episode,
        'seasons': seasons,
    })


def play(request, rating_key):
    # CMiVideoPlayer's "seconds" parameter and position callbacks are really in milliseconds, same as Plex
    offset = int(client.metadata(rating_key).get('viewOffset', 0))
    # Plex needs the token as a query parameter, but CMiVideoPlayer treats the query string as its own
    # parameters, so we give it a local URL that redirects to the real stream instead.
    subprocess.call(['open', 'CMiVideoPlayer://http://127.0.0.1:19817/plex/%s/stream?seconds=%s&callback=plex/%s' % (rating_key, offset, rating_key)])
    return HttpResponse(':back')


def stream(request, rating_key):
    return HttpResponseRedirect(client.part_url(rating_key))


def ended(request, rating_key):
    client.scrobble(rating_key)
    return HttpResponse(':nothing')


def position(request, rating_key, position):
    client.report_progress(rating_key, position)
    return HttpResponse(':nothing')
