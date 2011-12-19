from CMi.engine import playable_path
from django.http import HttpResponse
from django.shortcuts import render, get_object_or_404
from CMi.movies.models import *
import subprocess

def index(request):
    return render(request, 'movies/index.html', {'movies': Movie.objects.filter(watched=False)})

def play_movie(request, movie_id):
    movie = get_object_or_404(Movie, pk=movie_id)
    path = playable_path(movie.filepath)
    subprocess.call(['open', 'CMiVideoPlayer://%s?seconds=%s&callback=movies/%s' % (path, movie.position, movie.pk)])
    return render(request, 'playing.html', {})

def movie_ended(request, movie_id):
    movie = get_object_or_404(Movie, pk=movie_id)
    movie.watched = True
    movie.save()
    return HttpResponse('ok')

def movie_position(request, movie_id, position):
    movie = get_object_or_404(Movie, pk=movie_id)
    movie.position = position
    movie.save()
    return HttpResponse('ok')