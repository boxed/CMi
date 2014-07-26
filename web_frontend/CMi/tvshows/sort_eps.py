#!/usr/bin/env python
from shutil import move
from datetime import datetime, date
from CMi.engine import canonical_format, splitext
from CMi.tvshows.models import *
from CMi.directories import *
from send2trash.plat_osx import send2trash
import tvdb

tvdb.API_KEY = "1645288C00EAD78F"

DEBUG = False

def delete_watched_episodes():
    for episode in Episode.objects.filter(watched=True).exclude(filepath=''):
        if episode.show.auto_erase and episode.filepath:
            try:
                send2trash(episode.filepath)
            except OSError:
                pass
            episode.filepath = ''
            episode.save()

def clean_episode_db():
    #print 'cleaning episode db...'
    if not os.path.exists(tv_shows_dir):
        return
    for episode in Episode.objects.all():
        if not os.path.exists(episode.filepath) and episode.filepath:
            episode.filepath = ''
            episode.save()

# clean up empty directories
def clean_empty_dirs():
    #print 'cleaning dirs...'
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
                #print 'removing directory',subdir
                if not DEBUG:
                    send2trash(subdir)
                continue
            for subdir2 in get_subdirs(subdir):
                if not has_subs(subdir2):
                    #print 'removing directory',subdir2
                    if not DEBUG:
                        send2trash(subdir2)

def run_tv_shows_cleanup():
    delete_watched_episodes()
    clean_episode_db()
    clean_empty_dirs()

def run_tv_shows_extra():
    fetch_description()

series_data = {}
def get_series_data(series_name):
    series_name = series_name.lower()
    global series_data
    if series_name not in series_data:
        #print 'getting data for', series_name
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

def fetch_description():
    for episode in Episode.objects.filter(name='').exclude(filepath=''):
        #print 'fetching data for', episode
        try:
            if episode.episode:
                data = get_series_data(episode.show.name)['season_episode']['%s %s' % (episode.season, episode.episode)]
            else:
                data = get_series_data(episode.show.name)['aired'][episode.aired]
            episode.name = data['name']
            episode.description = data['overview']
            episode.save()
        except KeyError:
            pass
        except:
            import traceback
            print '---'
            print 'Failed to fetch data for episode', episode
            traceback.print_exc()
            print '---'
    global series_data
    series_data.clear()
    #print 'cleared cache'

def add_episode(data):
    type, filename, show_name = data[0], data[1], data[2]
    assert type == 'tv show'
    print data

    destination_dir = tv_shows_dir
    aired = None
    episode = 0
    show = Show.objects.get(canonical_name__exact=canonical_format(show_name))
    extension = splitext(filename)[-1].strip('. ')
    if isinstance(data[3], datetime):
        aired = data[3]
        season = aired.year
        destination = os.path.join(destination_dir, show.name, 'Season %s' % season, '%s %s.%s' % (show_name, aired.strftime('%Y-%m-%d'), extension))
    else:
        season, episode = data[3]
        destination = os.path.join(destination_dir, show.name, 'Season %s' % int(season), '%s S%02dE%02d.%s' % (show_name, season, episode, extension))
    if destination:
        print 'move %s -> %s' % (os.path.join(downloads_dir, filename), destination)
        if not DEBUG:
            try:
                os.makedirs(os.path.split(destination)[0])
            except:
                pass
            move(os.path.join(downloads_dir, filename), destination)
        Episode.objects.create(season=season, episode=episode, aired=aired, filepath=destination, show=show)
        return True
    return False

is_not_tv_show_cache = set()
def handle_tv_show_episode(data):
    type, filename, show_name = data[0], data[1], data[2]
    show_name = canonical_format(show_name)
    assert type == 'tv show'
    if Show.objects.filter(canonical_name__exact=show_name).count():
        add_episode(data)
        print 'added episode', data
        return True
    else:
        if show_name in is_not_tv_show_cache:
            return False
        matches = tvdb.get_series(show_name)
        match = None
        for m in matches:
            if canonical_format(m['name']) == show_name:
                match = m
                break
        if match:
            if not SuggestedShow.objects.filter(name=match['name']).count():
                SuggestedShow.objects.create(name=match['name'])
                print 'found potential new show "%s"' % show_name
                return True
        else:
            print 'did not find', show_name, 'on tvdb, ignoring...'
            is_not_tv_show_cache.add(show_name)
    return False