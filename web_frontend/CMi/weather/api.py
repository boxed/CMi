from django.utils.safestring import mark_safe
from django.template.loader import render_to_string
from django.conf.urls import patterns
from datetime import datetime, timedelta

def tiles():
    weather = get_weather()
    return [(30, render_to_string('tile.html', {
            'url': '',
            'image': weather['icon'] if weather else '',
            'title': 'Weather',
            'content': mark_safe('%s&deg;, %s%%' % (weather['temp'], weather['humidity'])) if weather else '',
        }))]

def urls():
    return patterns('CMi.weather.views',
        (r'^weather/$', 'index'),
        (r'^set_location/$', 'set_location'),
    )

_should_refresh = False
def should_refresh():
    global _should_refresh
    r = _should_refresh
    if _should_refresh:
        _should_refresh = False
    return r

location = None
weather_cache = None
def get_weather(place=None):
    global location
    if not place:
        place = location
    if not place:
        return None
    if place:
        location = place
    try:
        global weather_cache
        if weather_cache and (datetime.now() - weather_cache['cache_time']) < timedelta(hours=1):
            return weather_cache

        # Weather data from openweathermap
        from json import load
        from urllib2 import urlopen

        def celsius_from_kelvin(k):
            return k - 273.15

        lat, lon = location.split(',')

        url = 'http://api.openweathermap.org/data/2.5/weather/?lat=%s&lon=%s&APPID=846ecf80ab619e5cefb8cd58eb0c50ea' % (lat, lon)
        data = urlopen(url)
        data = load(data)
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
        global _should_refresh
        print 'should refresh GUI because weather data changed'
        _should_refresh = True
        return weather
    except Exception, e:
        print 'weather', e
        return None