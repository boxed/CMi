import os
import os.path
import subprocess
from django.http import HttpResponse
from django.shortcuts import render, get_object_or_404
from CMi.tvshows.models import *
from CMi.tvshows.sort_eps import SUPPORTED_FILE_FORMATS

def index(request):
    return render(request, 'tvshows/index.html', {'shows': Show.objects.all()})

def show(request, show_id):
    show = get_object_or_404(Show, pk=show_id)
    return render(request, 'tvshows/show.html', {'show': show})

def play_episode(request, show_id, episode_id):
    episode = get_object_or_404(Episode, pk=episode_id)
    path = episode.filepath
    if os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            if 'Sample' in root:
                continue
            for f in files:
                extension = os.path.splitext(f)[1]
                if extension in SUPPORTED_FILE_FORMATS:
                    path = os.path.join(root, f)
                    break
    print 'playing ', episode, 'at', path
    subprocess.call(['open', 'CMiVideoPlayer://%s?seconds=%s&callback=tvshows/%s/%s' % (path, episode.position, episode.show.pk, episode.pk)])
    return render(request, 'playing.html', {})

def episode_ended(request, show_id, episode_id):
    episode = get_object_or_404(Episode, pk=episode_id)
    episode.watched = True
    episode.save()
    return HttpResponse('ok')

def episode_position(request, show_id, episode_id, position):
    episode = get_object_or_404(Episode, pk=episode_id)
    episode.position = position
    episode.save()
    return HttpResponse('ok')