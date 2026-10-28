from django.template.loader import render_to_string
from django.conf.urls import patterns
from CMi.plex import client


def tiles():
    if not client.config():
        return []
    return [
        (25, render_to_string('tile.html', {
            'url': '/plex/',
            'image': '/site-media/folders.svg',
            'title': 'Plex',
        })),
    ]

def urls():
    return patterns('CMi.plex.views',
        (r'^plex/$', 'index'),
        (r'^plex/section/(?P<section_id>\d+)/$', 'section'),
        (r'^plex/show/(?P<show_id>\d+)/$', 'show'),
        (r'^plex/(?P<rating_key>\d+)/$', 'play'),
        (r'^plex/(?P<rating_key>\d+)/stream$', 'stream'),
        (r'^plex/(?P<rating_key>\d+)/ended$', 'ended'),
        (r'^plex/(?P<rating_key>\d+)/position/(?P<position>\d+)$', 'position'),
    )
