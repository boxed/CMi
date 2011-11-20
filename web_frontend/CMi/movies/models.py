from django.db import models

class Movie(models.Model):
    name = models.CharField(max_length=200)
    aired = models.CharField(blank=True, max_length=200)
    description = models.TextField(blank=True, null=True)
    watched = models.BooleanField(default=False)
    position = models.FloatField(default=0)
    filepath = models.TextField()
    
    def __unicode__(self):
        return self.name
    
    class Meta:
        ordering = ['name']