from django.db import models

class Show(models.Model):
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)

    def __unicode__(self):
        return '%s' % (self.name)
    
    class Meta:
        ordering = ['name']
        
    def unwatched_episodes(self):
        return self.episodes.filter(watched=False)

class Episode(models.Model):
    show = models.ForeignKey(Show, related_name='episodes')
    name = models.CharField(max_length=200)
    season = models.IntegerField()
    episode = models.IntegerField(default=0)
    aired = models.DateField(blank=True, null=True)
    description = models.TextField(blank=True, null=True)
    watched = models.BooleanField(default=False)
    position = models.FloatField(default=0)
    filepath = models.TextField()
    
    def __unicode__(self):
        return '%s s%se%s %s' % (self.show, self.season, self.episode, self.name)

    def description(self):
        if self.episode:
            return 'Season %s Episode %s %s' % (self.season, self.episode, self.name)
        else:
            return '%s %s' % (self.aired, self.name)
    
    class Meta:
        ordering = ['season', 'episode', 'aired']