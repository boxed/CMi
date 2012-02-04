from CMi.engine import playable_path
from django.http import HttpResponse
from django.shortcuts import render
from os.path import expanduser, split
from os import listdir

def browse(request, path):
    if not path:
        path = expanduser('~/Downloads')
    objects = [x for x in sorted(listdir(path)) if not x.startswith('.')]
    return render(request, 'filesystem/browse.html', {'objects': objects, 'path': path, 'title': split(path)[-1]})
