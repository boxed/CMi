from django.template.loader import render_to_string
from django.urls import re_path
from CMi.tvshows.models import Episode, Category

def tv_show_tile(title, episodes, category=None):
    return (
        10, render_to_string('tile.html', {
            'url': '/tvshows/' + (('category/%s/' % category.pk) if category else ''),
            'image': '/site-media/tv.svg',
            'title': title,
            'content': '%s new / %s total' % (episodes.filter(watched=False).count(), episodes.count()),
        }))

def tiles():
    return [tv_show_tile(title='TV Shows', episodes=Episode.objects.filter(show__category=None).exclude(filepath=''))] + [tv_show_tile(category=category, title=category.name, episodes=Episode.objects.filter(show__category=category).exclude(filepath='')) for category in Category.objects.order_by('name')]


def urls():
    from CMi.tvshows import views
    return [
        re_path(r'^tvshows/$', views.index),
        re_path(r'^tvshows/category/(?P<category_id>\d+)/$', views.index),
        re_path(r'^tvshows/(?P<show_id>\d+)/$', views.episode_list),
        re_path(r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/$', views.play_episode),
        re_path(r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/ended$', views.episode_ended),
        re_path(r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/position/(?P<position>\d+)$', views.episode_position),
        re_path(r'^tvshows/suggested/$', views.suggested_shows),
        re_path(r'^tvshows/suggested/(?P<suggested_show_id>\d+)/add/(?P<option>.*)/$', views.add_suggested_show),
        re_path(r'^tvshows/suggested/(?P<suggested_show_id>\d+)/ignore/$', views.ignore_suggested_show),
    ]
