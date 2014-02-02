from django.contrib import admin
from CMi.tvshows.models import *

class ShowAdmin(admin.ModelAdmin):
    pass

admin.site.register(Show, ShowAdmin)

class EpisodeAdmin(admin.ModelAdmin):
    list_filter = ('show', 'season')

admin.site.register(Episode, EpisodeAdmin)
admin.site.register(SuggestedShow)

