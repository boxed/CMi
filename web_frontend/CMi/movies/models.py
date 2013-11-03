from functools import total_ordering
from CMi.utils import title_sort_key
from django.db import models

@total_ordering
class Movie(models.Model):
    name = models.CharField(max_length=200)
    aired = models.CharField(blank=True, max_length=200)
    description = models.TextField(blank=True, null=True)
    watched = models.BooleanField(default=False)
    position = models.FloatField(default=0)
    filepath = models.TextField()
    
    def __unicode__(self):
        return self.name

    def description(self):
        return self.aired

    def url(self):
        return '/movies/%s' % self.id
    
    class Meta:
        ordering = ['name']

    def __eq__(self, other):
        return self.name == other.name

    def __lt__(self, other):
        return title_sort_key(self.name) == title_sort_key(other.name)
