from functools import total_ordering
from CMi.utils import title_sort_key
from django.db import models

@total_ordering
class Show(models.Model):
    name = models.CharField(max_length=200, unique=True)
    description = models.TextField(blank=True)
    canonical_name = models.CharField(max_length=200)
    auto_erase = models.BooleanField(default=True)
    source = models.CharField(max_length=255, blank=True)
    ended = models.BooleanField(default=False)

    def __unicode__(self):
        return '%s' % self.name

    def unwatched_episodes(self):
        if self.auto_erase:
            return self.episodes.filter(watched=False).exclude(filepath='')
        else:
            return self.episodes.exclude(filepath='')

    def __eq__(self, other):
        if not isinstance(other, Show):
            return False
        return self.name == other.name

    def __lt__(self, other):
        return title_sort_key(self.name) == title_sort_key(other.name)

    class Meta:
        ordering = ['name']

class SuggestedShow(models.Model):
    name = models.CharField(max_length=200, unique=True)
    ignored = models.BooleanField(default=False)

    def __unicode__(self):
        if self.ignored:
            return 'ignored: %s' % self.name
        else:
            return self.name

    class Meta:
        ordering = ['name']

class Episode(models.Model):
    show = models.ForeignKey(Show, related_name='episodes')
    name = models.CharField(max_length=200)
    season = models.IntegerField()
    episode = models.IntegerField(default=0)
    aired = models.DateField(blank=True, null=True)
    description = models.TextField(blank=True, null=True)
    watched = models.BooleanField(default=False)
    position = models.FloatField(default=0)
    filepath = models.TextField(blank=True)
    watched_count = models.IntegerField(default=False)

    def __unicode__(self):
        if self.aired:
            return '%s %s' % (self.show, self.aired)
        else:
            return '%s s%se%s %s' % (self.show, self.season, self.episode, self.name)

    class Meta:
        ordering = ['show__name', 'season', 'episode', 'aired']

    def watched_range(self):  # used by template
        return xrange(self.watched_count)