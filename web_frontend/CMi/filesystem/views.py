from CMi.utils import ListItem, chunks
from django.shortcuts import render
from os.path import expanduser
from os import listdir

def browse(request):
    path = request.GET.get('path', expanduser('~/Downloads'))
    objects = ['..'] + [x for x in sorted(listdir(path)) if not x.startswith('.')]
    objects = [ListItem('/browse/?path=%s/%s' % (path, o), o) for o in objects]
    title = path.split('/')[-1]
    if not title:
        title = path.split('/')[-2]

    columns = [x for x in chunks(objects, 10, pad=True)]
    rows = zip(*columns)

    return render(request, 'list.html', {'rows': rows, 'title': title})
