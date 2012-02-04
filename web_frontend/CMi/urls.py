from django.conf.urls.defaults import *
from django.conf import settings

from django.contrib import admin
admin.autodiscover()

urlpatterns = patterns('',
    # Example:
    # (r'^CMi/', include('CMi.foo.urls')),
    (r'^$', 'CMi.views.index'),
    (r'^weather/$', 'CMi.views.weather'),
    (r'^tvshows/', include('CMi.tvshows.urls')),
    (r'^movies/', include('CMi.movies.urls')),
    (r'^filesystem/', include('CMi.filesystem.urls')),
    (r'^search_for_new_files/', 'CMi.views.search_for_new_files'),
    (r'^set_location/', 'CMi.views.set_location'),

    #(r'^telldus/(?P<id>\d+)/(?P<command>.+)$', 'CMi.views.telldus'),

    # Uncomment the admin/doc line below and add 'django.contrib.admindocs' 
    # to INSTALLED_APPS to enable admin documentation:
    # (r'^admin/doc/', include('django.contrib.admindocs.urls')),

    url(r'^site-media/(?P<path>.*)$', 'django.views.static.serve', {'document_root': settings.MEDIA_ROOT}),

    (r'^admin/', include(admin.site.urls)),
)
