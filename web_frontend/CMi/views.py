from datetime import datetime, timedelta
from threading import Thread
from CMi.movies.sort_movies import handle_movie, run_movies_cleanup
from CMi.tvshows.sort_eps import handle_tv_show_episode, run_tv_shows_cleanup, run_tv_shows_extra
from django.http import HttpResponse
from django.shortcuts import render
import pywapi
from CMi.tvshows.models import *
from CMi.movies.models import *
from CMi.engine import match_file, find_videos

#def telldus_command(id, command):
#    os.system('arch -i386 /usr/bin/python2.6 CMi/tellstick.py %s %s' % (command, id))

weather_icon_translation = {
    '/ig/images/weather/sunny.gif': '/site-media/weather/sun.svg',
    '/ig/images/weather/mostly_sunny.gif': '/site-media/weather/sun.svg',
    '/ig/images/weather/rain.gif': '/site-media/weather/rain.svg',
    '/ig/images/weather/chance_of_rain.gif': '/site-media/weather/rain.svg',

    '/ig/images/weather/partly_cloudy.gif': '/site-media/weather/partly_cloudy.svg',
    '/ig/images/weather/mostly_cloudy.gif': '/site-media/weather/partly_cloudy.svg',
    '/ig/images/weather/cloudy.gif': '/site-media/weather/cloud.svg',

    '/ig/images/weather/mist.gif': '/site-media/weather/fog.svg',
    '/ig/images/weather/fog.gif': '/site-media/weather/fog.svg',

    '/ig/images/weather/storm.gif': '/site-media/weather/wind.svg',
    '/ig/images/weather/chance_of_storm.gif': '/site-media/weather/wind.svg',
    '/ig/images/weather/thunderstorm.gif': '/site-media/weather/wind.svg',
    '/ig/images/weather/chance_of_tstorm.gif': '/site-media/weather/wind.svg',

    '/ig/images/weather/sleet.gif': '/site-media/weather/snow.svg', # really hail
    '/ig/images/weather/snow.gif': '/site-media/weather/snow.svg',
    '/ig/images/weather/chance_of_snow.gif': '/site-media/weather/snow.svg',

#    '/ig/images/weather/icy.gif': '',
#    '/ig/images/weather/dust.gif': '',
#    '/ig/images/weather/smoke.gif': '',
#    '/ig/images/weather/haze.gif': '',
#    '/ig/images/weather/flurries.gif': '',
}

def fix_icon_path(s):
    if s in weather_icon_translation:
        return weather_icon_translation[s]
    else:
        print 'no weather icon for', s
        return ''

location = None
weather_cache = None
def get_weather(place=None):
    global location
    if not place:
        place = location
    if not place:
        return None
    try:
        global weather_cache
        if weather_cache and (datetime.now() - weather_cache['cache_time']) < timedelta(hours=1):
            return weather_cache
        weather = pywapi.get_weather_from_google(place)
        weather['current_conditions']['icon'] = fix_icon_path(weather['current_conditions']['icon'])
        # convert temperatures to celsius
        for value in weather['forecasts']:
            value['high'] = int(round((float(value['high'])-32)*5.0/9.0))
            value['low'] = int(round((float(value['low'])-32)*5.0/9.0))
            value['icon'] = fix_icon_path(value['icon'])
        weather_cache = weather
        weather_cache['cache_time'] = datetime.now()
        global should_refresh
        print 'should refresh GUI because wheather data changed'
        should_refresh = True
        return weather
    except:
        return None

search_thread = None
should_refresh = False
files_that_match_nothing = set()
def search_for_new_files(request):
    def do_search():
        global files_that_match_nothing
        refresh = False
        for video in find_videos():
            if video in files_that_match_nothing:
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
            else:
                files_that_match_nothing.add(video)
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
    result = ':refresh' if should_refresh else ':nothing'
    should_refresh = False
    return HttpResponse(result)

def index(request):
    c = {
        'weather': get_weather(),
        'new_episodes': Episode.objects.filter(watched=False).count(),
        'new_shows': SuggestedShow.objects.filter(ignored=False).count(),
        'new_movies': Movie.objects.filter(watched=False).count(),
        'total_movies': Movie.objects.filter().count(),
    }
    return render(request, 'index.html', c)
    
def weather(request):
    weather = get_weather()
    return render(request, 'weather.html', {'weather': weather})

def set_location(request):
    global location
    location = ',,,'+request.REQUEST['location'].replace('.', '')
    get_weather()
    return HttpResponse(':nothing')

#def telldus(request, id, command):
#   telldus_command(id, command)
#   return render(request, 'telldus_on.html', {'id': id})