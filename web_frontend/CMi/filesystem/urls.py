from django.conf.urls.defaults import *

urlpatterns = patterns('CMi.filesystem.views',
    (r'^browse/(?P<path>.*)$', 'browse'),
)
