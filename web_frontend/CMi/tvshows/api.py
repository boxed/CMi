from django.template.loader import render_to_string
from django.conf.urls import patterns
from CMi.tvshows.models import Episode


def tiles():
    return [
        (10, render_to_string('tile.html', {
            'url': '/tvshows/',
            'image': '/site-media/tv.svg',
            'title': 'TV Shows',
            'content': '%s new episodes' % Episode.objects.filter(watched=False).exclude(filepath='').count(),
        })),
    ]


def urls():
    return patterns('CMi.tvshows.views',
        (r'^tvshows/$', 'index'),
        (r'^tvshows/(?P<show_id>\d+)/$', 'episode_list'),
        (r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/$', 'play_episode'),
        (r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/ended$', 'episode_ended'),
        (r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/position/(?P<position>\d+)$', 'episode_position'),
        (r'^tvshows/suggested/$', 'suggested_shows'),
        (r'^tvshows/suggested/(?P<suggested_show_id>\d+)/add/(?P<option>.*)/$', 'add_suggested_show'),
        (r'^tvshows/suggested/(?P<suggested_show_id>\d+)/ignore/$', 'ignore_suggested_show'),
    )