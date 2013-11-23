from django.shortcuts import render
from os.path import expanduser
from os import listdir

def browse(request):
    path = request.GET.get('path', expanduser('~/Downloads'))
    objects = ['..'] + [x for x in sorted(listdir(path)) if not x.startswith('.')]
    class Item(object):
        def __init__(self, o):
            self.path = path
            self.o = o
        def url(self):
            return '/browse/?path=%s/%s' % (self.path, self.o)
        def __unicode__(self):
            return self.o
    objects = [Item(o) for o in objects]
    title = path.split('/')[-1]
    if not title:
        title = path.split('/')[-2]
    return render(request, 'list.html', {'items': objects, 'title': title})
