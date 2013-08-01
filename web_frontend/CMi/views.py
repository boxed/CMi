from threading import Thread
from django.conf import settings
from django.utils import importlib
from django.utils.safestring import mark_safe
from CMi.movies.sort_movies import handle_movie, run_movies_cleanup
from CMi.tvshows.sort_eps import handle_tv_show_episode, run_tv_shows_cleanup, run_tv_shows_extra
from django.http import HttpResponse
from django.shortcuts import render
from CMi.engine import match_file, find_videos

plugin_api_modules = []
for app in settings.INSTALLED_APPS:
    try:
        plugin_api_modules.append(importlib.import_module(app+'.api'))
        print app
    except ImportError:
        pass

#def telldus_command(id, command):
#    os.system('arch -i386 /usr/bin/python2.6 CMi/tellstick.py %s %s' % (command, id))

def chunks(l, n):
    """ Yield successive n-sized chunks from l.
    """
    for i in xrange(0, len(l), n):
        yield l[i:i+n]


search_thread = None
should_refresh = False
handled_files = set()
def search_for_new_files(request):
    def do_search():
        global handled_files
        refresh = False
        for video in find_videos():
            if video in handled_files:
                continue
            m = match_file(video)
            if m:
                if m[0] == 'movie':
                    if handle_movie(m):
                        refresh = True
                        print 'found movie', m
                elif m[0] == 'tv show':
                    if handle_tv_show_episode(m):
                        refresh = True
                        print 'found tv show', m
            handled_files.add(video)
        run_tv_shows_cleanup()
        run_tv_shows_extra()
        run_movies_cleanup()
        global should_refresh
        should_refresh = refresh
        #print 'end search thread'
    global search_thread
    if not search_thread or not search_thread.is_alive():
        #print 'starting search thread...', search_thread
        search_thread = Thread(target=do_search)
        search_thread.start()
    global should_refresh
    for api in plugin_api_modules:
        if hasattr(api, 'should_refresh'):
            should_refresh = api.should_refresh() or should_refresh
    result = ':refresh' if should_refresh else ':nothing'
    should_refresh = False
    return HttpResponse(result)

def index(request):
    tiles = []
    for api in plugin_api_modules:
        if hasattr(api, 'tiles'):
            tiles.extend(api.tiles())

    tiles.sort()
    tiles = [mark_safe(tile) for _, tile in tiles]
    rows = chunks(tiles, 3)

    return render(request, 'index.html', {'rows': rows})
    
#def telldus(request, id, command):
#   telldus_command(id, command)
#   return render(request, 'telldus_on.html', {'id': id})