import chunk
import subprocess
from CMi.utils import title_sort_key, ListItem, chunks
from django.db import IntegrityError
from CMi.engine import playable_path, canonical_format
from django.http import HttpResponse
from django.shortcuts import render, get_object_or_404
from CMi.tvshows.models import *
import tvdb

def index(request):
    shows = sorted(Show.objects.all(), key=lambda x: title_sort_key(x.name))
    shows = [ListItem('/tvshows/%s' % show.pk, show.name, show.unwatched_episodes().count()) for show in shows if show.unwatched_episodes()]
    rows = chunks(shows, 2)
    return render(request, 'list.html', {'title': 'TV Shows', 'rows': rows})

def episode_list(request, show_id):
    return render(request, 'tvshows/show.html', {'show': get_object_or_404(Show, pk=show_id)})

def play_episode(request, show_id, episode_id):
    episode = get_object_or_404(Episode, pk=episode_id)
    path = playable_path(episode.filepath)
    print 'playing ', episode, 'at', path
    subprocess.call(['open', 'CMiVideoPlayer://%s?seconds=%s&callback=tvshows/%s/%s' % (path, episode.position, episode.show.pk, episode.pk)])
    return HttpResponse(':back')

def episode_ended(request, show_id, episode_id):
    episode = get_object_or_404(Episode, pk=episode_id)
    episode.watched = True
    episode.save()
    return HttpResponse(':nothing')

def episode_position(request, show_id, episode_id, position):
    episode = get_object_or_404(Episode, pk=episode_id)
    episode.position = position
    episode.save()
    return HttpResponse(':nothing')

def suggested_shows(request):
    return render(request, 'tvshows/suggested_shows.html', {'suggested_shows': SuggestedShow.objects.filter(ignored=False)})

def add_suggested_show(request, suggested_show_id, option):
    s = SuggestedShow.objects.get(pk=suggested_show_id)
    tvdb_result = tvdb.get_series(s.name)
    description = tvdb_result[0]['overview'] if len(tvdb_result) else ''
    try:
        Show.objects.create(name=s.name, description=description, canonical_name=canonical_format(s.name), auto_erase=(option=='erase'))
    except IntegrityError:
        pass
    s.delete()
    if SuggestedShow.objects.filter(ignored=False).count():
        return HttpResponse(':back')
    else:
        return HttpResponse(':back2')

def ignore_suggested_show(request, suggested_show_id):
    s = SuggestedShow.objects.get(pk=suggested_show_id)
    s.ignored = True
    s.save()
    if SuggestedShow.objects.all().count():
        return HttpResponse(':back')
    else:
        return HttpResponse(':back2')
