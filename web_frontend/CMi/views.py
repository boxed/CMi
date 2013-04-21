from datetime import datetime, timedelta
from threading import Thread
from CMi.movies.sort_movies import handle_movie, run_movies_cleanup
from CMi.tvshows.sort_eps import handle_tv_show_episode, run_tv_shows_cleanup, run_tv_shows_extra
from django.http import HttpResponse
from django.shortcuts import render
from CMi.tvshows.models import *
from CMi.movies.models import *
from CMi.engine import match_file, find_videos

#def telldus_command(id, command):
#    os.system('arch -i386 /usr/bin/python2.6 CMi/tellstick.py %s %s' % (command, id))

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

        # Weather data from openweathermap
        from json import load
        from urllib2 import urlopen

        def celsius_from_kelvin(k):
            return k - 273.15

        data = urlopen('http://openweathermap.org/data/2.1/find/city?lat=59.416365&lon=17.961050&radius=10')
        data = load(data)['list'][0]
        # from pprint import pprint
        # pprint(data)
        temp = int(round(celsius_from_kelvin(data['main']['temp'])))
        temp_max = int(round(celsius_from_kelvin(data['main']['temp_max'])))
        temp_min = int(round(celsius_from_kelvin(data['main']['temp_min'])))

        # Convert the weather codes from http://openweathermap.org/wiki/API/Weather_Condition_Codes to the images in CMi
        weather_code = int(str(data['weather'][0]['id'])[0])
        if weather_code == 8:
            weather_code = data['weather'][0]['id']
        if data['weather'][0]['id'] == 905:
            weather_code = 905
        weather_code_to_icon_name = {
            # 1: ???
            2: 'lightning', # thunderstorm
            3: 'rain', # drizzle
            # 4: ???
            5: 'rain',
            6: 'snow',
            7: 'fog',
            800: 'sun', # or clear_night if it's night time
            801: 'partly_cloudy',
            802: 'cloud',
            803: 'cloud',
            804: 'cloud',
            # 9: extreme
            905: 'wind',
        }
        weather_image = '/site-media/weather/'+weather_code_to_icon_name[weather_code]+'.svg'

        weather = {
            'icon': weather_image,
            'temp': temp,
            'temp_max': temp_max,
            'temp_min': temp_min,
            'humidity': data['main']['humidity']
        }

        weather_cache = weather
        weather_cache['cache_time'] = datetime.now()
        global should_refresh
        print 'should refresh GUI because weather data changed'
        should_refresh = True
        return weather
    except Exception:
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