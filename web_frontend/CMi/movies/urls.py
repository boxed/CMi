from django.conf.urls import patterns

urlpatterns = patterns('CMi.movies.views',
    (r'^$', 'index'),
    (r'^(?P<movie_id>\d+)/$', 'play_movie'),
    (r'^(?P<movie_id>\d+)/ended$', 'movie_ended'),
    (r'^(?P<movie_id>\d+)/position/(?P<position>\d+)$', 'movie_position'),
)
