from django.http import HttpResponse
from django.shortcuts import render
import pywapi
from CMi.tvshows.models import *
from CMi.tvshows import sort_eps
from CMi.movies import sort_movies
from CMi.movies.models import *
import threading
import os

#def telldus_command(id, command):
#    os.system('arch -i386 /usr/bin/python2.6 CMi/tellstick.py %s %s' % (command, id))

def fix_icon_path(s):
    return s.replace('/ig/images/weather/', '').replace('.gif', '.png')

def get_weather(place='Stockholm,Sweden'):
    try:
        weather = pywapi.get_weather_from_google(place)
        weather['current_conditions']['icon'] = fix_icon_path(weather['current_conditions']['icon'])
        # convert temperatures to celcius
        for value in weather['forecasts']:
            value['high'] = int(round((float(value['high'])-32)*5.0/9.0))
            value['low'] = int(round((float(value['low'])-32)*5.0/9.0))
            value['icon'] = fix_icon_path(value['icon'])
        return weather
    except:
        return None

def index(request):
    threading.Thread(target=sort_eps.do_all).start()
    threading.Thread(target=sort_movies.do_all).start()
    #threading.Thread(target=telldus_command, args=(2, 'on')).start()
    c = {
        'weather': get_weather(),
        'new_episodes': Episode.objects.filter(watched=False).count(),
        'new_movies': Movie.objects.filter(watched=False).count(),
        'total_movies': Movie.objects.filter().count(),
    }
    return render(request, 'index.html', c)
    
def weather(request):
    if 'place' in request.REQUEST:
        place = request.REQUEST['place']
    else:
        place = 'Stockholm,Sweden'
    weather = get_weather(place)
    return render(request, 'weather.html', {'weather': weather})

#def telldus(request, id, command):
#   telldus_command(id, command)
#   return render(request, 'telldus_on.html', {'id': id})