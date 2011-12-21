import os
import os.path
import subprocess
from CMi.engine import SUPPORTED_FILE_FORMATS, playable_path, canonical_format
from django.http import HttpResponse
from django.shortcuts import render, get_object_or_404
from CMi.tvshows.models import *
import tvdb

def index(request):
    return render(request, 'tvshows/index.html', {'shows': Show.objects.all()})

def show(request, show_id):
    show = get_object_or_404(Show, pk=show_id)
    return render(request, 'tvshows/show.html', {'show': show})

def play_episode(request, show_id, episode_id):
    episode = get_object_or_404(Episode, pk=episode_id)
    path = playable_path(episode.filepath)
    print 'playing ', episode, 'at', path
    subprocess.call(['open', 'CMiVideoPlayer://%s?seconds=%s&callback=tvshows/%s/%s' % (path, episode.position, episode.show.pk, episode.pk)])
    return render(request, 'playing.html', {})

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

def add_suggested_show(request, suggested_show_id):
    s = SuggestedShow.objects.get(pk=suggested_show_id)
    description = tvdb.get_series(s.name)[0]['overview'] or ''
    Show.objects.create(name=s.name, description=description, canonical_name=canonical_format(s.name))
    s.delete()
    if SuggestedShow.objects.all().count():
        return HttpResponse(':refresh')
    else:
        return HttpResponse(':back')

def ignore_suggested_show(request, suggested_show_id):
    s = SuggestedShow.objects.get(pk=suggested_show_id)
    s.ignore = True
    if SuggestedShow.objects.all().count():
        return HttpResponse(':refresh')
    else:
        return HttpResponse(':back')
    