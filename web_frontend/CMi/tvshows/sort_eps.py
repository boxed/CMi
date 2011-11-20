#!/usr/bin/env python
import os
from os.path import join, getsize, splitext
import re
from shutil import move
from datetime import datetime, date
from tvshows.models import *
from CMi.directories import *
import tvdb

tvdb.API_KEY = "1645288C00EAD78F"

DEBUG = False

season_ep_regexs = [
                    '(?P<name>.*)s(?P<season>\d\d)e(?P<episode>\d\d)',
                    '(?P<name>.*)\[(?P<season>\d\d?)x(?P<episode>\d\d)[.\]]',
                    '(?P<name>.*)[. ](?P<season>\d\d?)x(?P<episode>\d\d)[. ]',
                    '(?P<name>.*)(?P<season>\d\d?)(?P<episode>\d\d)',
                    ]
date_regexs = [
               '.*(?P<year>\d\d\d\d).(?P<month>\d\d).(?P<day>\d\d)'
               ]


def delete_watched_episodes():
    for episode in Episode.objects.filter(watched=True):
        send_to_trash(episode.filepath)
        episode.delete()
    
def clean_episode_db():
    print 'cleaning episode db...'
    if not os.path.exists(tv_shows_dir):
        print 'entire path missing, aborting...'
        return
    for episode in Episode.objects.all():
        if not os.path.exists(episode.filepath):
            episode.delete()

# clean up empty directories
def clean_empty_dirs():
    print 'cleaning dirs...'
    def get_subdirs(path):
        for root, dirs, files in os.walk(path):
            return [os.path.join(root, x) for x in dirs]
        return []

    def has_subs(path):
        for root, dirs, files in os.walk(path):
            files = [x for x in files if not x.startswith('.')]
            return len(dirs)+len(files) != 0
        return False

    for show_dir in get_subdirs(tv_shows_dir):
        for subdir in get_subdirs(show_dir):
            if not has_subs(subdir):
                print 'removing directory',subdir
                if not DEBUG:
                    send_to_trash(subdir)
                continue
            for subdir2 in get_subdirs(subdir):
                if not has_subs(subdir2):
                    print 'removing directory',subdir2
                    if not DEBUG:
                        send_to_trash(subdir2)
                        
def canonical_format(s):
    return s.replace('.', ' ').replace('_', ' ').lower().replace('&', 'and').replace("'", '').strip()

def sort_episodes():    
    print 'sorting episodes...'
    destination_dir = tv_shows_dir
    shows = Show.objects.all()
    global season_ep_regexs
    global date_regexs

    videos = []
    for root, dirs, files in os.walk(downloads_dir):
        for f in files:
            if supported_extension(f):
                for show in shows:
                    if canonical_format(show.name) in canonical_format(f):
                        videos.append((show, f))
        for d in dirs:
            if d in ('Movies', 'TV Shows', 'Incomplete'):
                continue
            for show in shows:
                if canonical_format(show.name) in canonical_format(d):
                    videos.append((show, d))
        break

    for show, video in videos[:]:
        destination = None
        aired = None
        episode = 0
        m = None
        for season_ep_regex in season_ep_regexs:
            m = re.match(season_ep_regex, video.lower())
            if m:
                break
        if m:
            season, episode = m.groupdict()['season'], m.groupdict()['episode']
            destination = os.path.join(destination_dir, show.name, 'Season %s' % int(season), video) 
        else:
            for date_regex in date_regexs:
                m = re.match(date_regex, video)
                if m:
                    break
            if m:
                aired = datetime(int(m.groupdict()['year']), int(m.groupdict()['month']), int(m.groupdict()['day']))
                season = aired.year
                destination = os.path.join(destination_dir, show.name, 'Season %s' % season, video)
        if destination:
            print 'move %s -> %s' % (os.path.join(downloads_dir, video), destination)
            if not DEBUG:
                try:
                    os.makedirs(os.path.split(destination)[0])
                except:
                    pass
                move(os.path.join(downloads_dir, video), destination)
            videos.remove((show, video))
            Episode.objects.create(season=season, episode=episode, aired=aired, filepath=destination, show=show)

    if len(videos) != 0:
        print "didn't sort the following:"
        for x in videos:
            print '\t', x
            
series_data = {}
def get_series_data(series_name):
    series_name = series_name.lower()
    global series_data
    if series_name not in series_data:
        print 'getting data for', series_name
        if series_name == 'the daily show':
            series = tvdb.get_series('The Daily Show with Jon Stewart')[0]
        else:
            series = tvdb.get_series(series_name)[0]
        raw_data = tvdb.get_series_all(series['id'])
        series_data[series_name] = {'season_episode': {}, 'aired': {}}
        for data in raw_data['episodes']:
            if 'season_number' in data and 'episode_number' in data:
                series_data[series_name]['season_episode']['%s %s' % (data['season_number'], data['episode_number'])] = data
            if 'first_aired' in data and data['first_aired']:
                dt = data['first_aired']
                series_data[series_name]['aired'][date(dt.year, dt.month, dt.day)] = data
    return series_data[series_name]

def find_new_series():
    for video in find_videos():
        for season_ep_regex in season_ep_regexs:
            m = re.match(season_ep_regex, video.lower())
            if m:
                break
        if not m:
            for date_regex in date_regexs:
                m = re.match(date_regex, video)
                if m:
                    break
        if m:
            series_name = canonical_format(m.groupdict()['name'])
            if tvdb.get_series(series_name):
                print 'potential new series:', series_name

    
def fetch_description():
    for episode in Episode.objects.filter(name=''):
        print 'fetching data for', episode
        try:
            if episode.episode != 0:
                data = get_series_data(episode.show.name)['season_episode']['%s %s' % (episode.season, episode.episode)]
            else:
                data = get_series_data(episode.show.name)['aired'][episode.aired]
            episode.name = data['name']
            episode.description = data['overview']
            episode.save()
        except:
            import traceback
            print '---'
            print 'Failed to fetch data for episode', episode
            traceback.print_exc()
            print '---'

def do_all():
    delete_watched_episodes()
    clean_empty_dirs()
    clean_episode_db()
    sort_episodes()
    fetch_description()
    find_new_series()

if __name__ == '__main__':
    do_all()
