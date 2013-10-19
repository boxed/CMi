from django.http import HttpResponse
from django.shortcuts import render
from CMi.weather.api import get_weather

def index(request):
    weather = get_weather()
    return render(request, 'weather.html', {'weather': weather})

def set_location(request):
    get_weather(request.REQUEST['location'])
    return HttpResponse(':nothing')

