from django.conf import settings
from django.contrib import admin
from django.urls import path, re_path
from django.views.static import serve
from CMi import views
from CMi.views import plugin_api_modules

urlpatterns = [
    path('', views.index),
    re_path(r'^search_for_new_files/', views.search_for_new_files),
    re_path(r'^code_changed/', views.code_changed),
    re_path(r'^css/', views.css),
    re_path(r'^test/', views.test),

    re_path(r'^site-media/(?P<path>.*)$', serve, {'document_root': settings.MEDIA_ROOT}),

    path('admin/', admin.site.urls),
]

for api in plugin_api_modules:
    if hasattr(api, 'urls'):
        urlpatterns += api.urls()
