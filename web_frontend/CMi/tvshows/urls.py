from django.conf.urls.defaults import *

urlpatterns = patterns('CMi.tvshows.views',
    (r'^$', 'index'),
    (r'^(?P<show_id>\d+)/$', 'show'),
    (r'^(?P<show_id>\d+)/(?P<episode_id>\d+)/$', 'play_episode'),
    (r'^(?P<show_id>\d+)/(?P<episode_id>\d+)/ended$', 'episode_ended'),
    (r'^(?P<show_id>\d+)/(?P<episode_id>\d+)/position/(?P<position>\d+)$', 'episode_position'),
)
