from django.template.loader import render_to_string
from django.urls import re_path
from CMi.movies.models import Movie


def tiles():
    return [
        (20, render_to_string('tile.html', {
            'url': '/movies/',
            'image': '/site-media/movie.svg',
            'title': 'Movies',
            'content': '%s new / %s total' % (Movie.objects.filter(watched=False).count(),Movie.objects.filter().count())
        })),
    ]

def urls():
    from CMi.movies import views
    return [
        re_path(r'^movies/$', views.index),
        re_path(r'^movies/(?P<movie_id>\d+)/$', views.play_movie),
        re_path(r'^movies/(?P<movie_id>\d+)/ended$', views.movie_ended),
        re_path(r'^movies/(?P<movie_id>\d+)/position/(?P<position>\d+)$', views.movie_position),
    ]
