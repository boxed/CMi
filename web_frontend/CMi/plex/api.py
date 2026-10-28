from django.template.loader import render_to_string
from django.urls import re_path
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
    from CMi.plex import views
    return [
        re_path(r'^plex/$', views.index),
        re_path(r'^plex/section/(?P<section_id>\d+)/$', views.section),
        re_path(r'^plex/show/(?P<show_id>\d+)/$', views.show),
        re_path(r'^plex/(?P<rating_key>\d+)/$', views.play),
        re_path(r'^plex/(?P<rating_key>\d+)/stream$', views.stream),
        re_path(r'^plex/(?P<rating_key>\d+)/ended$', views.ended),
        re_path(r'^plex/(?P<rating_key>\d+)/position/(?P<position>\d+)$', views.position),
    ]
