from django.db import models

class Version(models.Model):
    app = models.CharField(max_length=1024)
    version = models.IntegerField(default=0)

    class Meta:
        ordering = ['app']