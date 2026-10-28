from django.template.loader import render_to_string
from django.urls import re_path


def tiles():
    return []
    # return [
    #     (100, render_to_string('tile.html', {
    #         'url': '/browse/',
    #         'image': '/site-media/folders.svg',
    #         'title': 'Browse Files',
    #     })),
    # ]

def urls():
    from CMi.filesystem import views
    return [
        re_path(r'^browse/$', views.browse),
    ]
