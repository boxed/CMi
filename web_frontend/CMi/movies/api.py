from django.template.loader import render_to_string
from django.conf.urls import patterns
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
    return patterns('CMi.movies.views',
        (r'^movies/$', 'index'),
        (r'^movies/(?P<movie_id>\d+)/$', 'play_movie'),
        (r'^movies/(?P<movie_id>\d+)/ended$', 'movie_ended'),
        (r'^movies/(?P<movie_id>\d+)/position/(?P<position>\d+)$', 'movie_position'),
    )