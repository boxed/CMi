from django.conf import settings
from django.conf.urls import patterns, include, url
from django.contrib import admin
from CMi.views import plugin_api_modules

admin.autodiscover()

urlpatterns = patterns('',
    (r'^$', 'CMi.views.index'),
    (r'^search_for_new_files/', 'CMi.views.search_for_new_files'),
    (r'^code_changed/', 'CMi.views.code_changed'),
    (r'^css/', 'CMi.views.css'),
    (r'^test/', 'CMi.views.test'),
                       
    # Uncomment the admin/doc line below and add 'django.contrib.admindocs'
    # to INSTALLED_APPS to enable admin documentation:
    # (r'^admin/doc/', include('django.contrib.admindocs.urls')),

    url(r'^site-media/(?P<path>.*)$', 'django.views.static.serve', {'document_root': settings.MEDIA_ROOT}),
    url(r'^media/admin/(?P<path>.*)$', 'django.views.static.serve', {'document_root': settings.MEDIA_ROOT+'/../../../django/contrib/admin/static/admin'}),

    (r'^admin/', include(admin.site.urls)),
)

for api in plugin_api_modules:
    if hasattr(api, 'urls'):
        urlpatterns += api.urls()
