from django.template.loader import render_to_string
from django.conf.urls import patterns


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
    return patterns('CMi.filesystem.views',
        (r'^browse/$', 'browse'),
    )