from django.conf.urls import patterns

urlpatterns = patterns('CMi.tvshows.views',
    (r'^$', 'index'),
    (r'^(?P<show_id>\d+)/$', 'show'),
    (r'^(?P<show_id>\d+)/(?P<episode_id>\d+)/$', 'play_episode'),
    (r'^(?P<show_id>\d+)/(?P<episode_id>\d+)/ended$', 'episode_ended'),
    (r'^(?P<show_id>\d+)/(?P<episode_id>\d+)/position/(?P<position>\d+)$', 'episode_position'),

    (r'^suggested/$', 'suggested_shows'),
    (r'^suggested/(?P<suggested_show_id>\d+)/add/(?P<option>.*)/$', 'add_suggested_show'),
    (r'^suggested/(?P<suggested_show_id>\d+)/ignore/$', 'ignore_suggested_show'),
)
