from django.conf.urls import patterns

urlpatterns = patterns('CMi.filesystem.views',
    (r'^browse/(?P<path>.*)$', 'browse'),
)
