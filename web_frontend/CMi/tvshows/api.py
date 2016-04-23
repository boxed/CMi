from django.template.loader import render_to_string
from django.conf.urls import patterns
from CMi.tvshows.models import Episode, Category

def tv_show_tile(title, episodes, category=None):
    return (
        10, render_to_string('tile.html', {
            'url': '/tvshows/' + (('category/%s/' % category.pk) if category else ''),
            'image': '/site-media/tv.svg',
            'title': title,
            'content': '%s new episodes' % episodes.count(),
        }))

def tiles():
    return [tv_show_tile(title='TV Shows', episodes=Episode.objects.filter(watched=False, show__category=None).exclude(filepath=''))] + [tv_show_tile(category=category, title=category.name, episodes=Episode.objects.filter(watched=False, show__category=category).exclude(filepath='')) for category in Category.objects.order_by('name')]


def urls():
    return patterns('CMi.tvshows.views',
        (r'^tvshows/$', 'index'),
        (r'^tvshows/category/(?P<category_id>\d+)/$', 'index'),
        (r'^tvshows/(?P<show_id>\d+)/$', 'episode_list'),
        (r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/$', 'play_episode'),
        (r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/ended$', 'episode_ended'),
        (r'^tvshows/(?P<show_id>\d+)/(?P<episode_id>\d+)/position/(?P<position>\d+)$', 'episode_position'),
        (r'^tvshows/suggested/$', 'suggested_shows'),
        (r'^tvshows/suggested/(?P<suggested_show_id>\d+)/add/(?P<option>.*)/$', 'add_suggested_show'),
        (r'^tvshows/suggested/(?P<suggested_show_id>\d+)/ignore/$', 'ignore_suggested_show'),
    )