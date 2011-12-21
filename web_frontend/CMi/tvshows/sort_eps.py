#!/usr/bin/env python
from shutil import move
from datetime import datetime, date
from CMi.engine import canonical_format
from CMi.tvshows.models import *
from CMi.directories import *
import tvdb
from threading import Thread

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

def run_tv_shows_cleanup():
    delete_watched_episodes()
    clean_episode_db()
    clean_empty_dirs()

def run_tv_shows_extra():
    Thread(target=fetch_description).start()

#def sort_episodes():
#    print 'sorting episodes...'
#    destination_dir = tv_shows_dir
#    shows = Show.objects.all()
#    global season_ep_regexs
#    global date_regexs
#
#    videos = []
#    for root, dirs, files in os.walk(downloads_dir):
#        for f in files:
#            if supported_extension(f):
#                for show in shows:
#                    if canonical_format(show.name) in canonical_format(f):
#                        videos.append((show, f))
#        for d in dirs:
#            if d in ('Movies', 'TV Shows', 'Incomplete'):
#                continue
#            for show in shows:
#                if canonical_format(show.name) in canonical_format(d):
#                    videos.append((show, d))
#        break
#
#    for show, video in videos[:]:
#        destination = None
#        aired = None
#        episode = 0
#        m = None
#        for season_ep_regex in season_ep_regexs:
#            m = re.match(season_ep_regex, video.lower())
#            if m:
#                break
#        if m:
#            season, episode = m.groupdict()['season'], m.groupdict()['episode']
#            destination = os.path.join(destination_dir, show.name, 'Season %s' % int(season), video)
#        else:
#            for date_regex in date_regexs:
#                m = re.match(date_regex, video)
#                if m:
#                    break
#            if m:
#                aired = datetime(int(m.groupdict()['year']), int(m.groupdict()['month']), int(m.groupdict()['day']))
#                season = aired.year
#                destination = os.path.join(destination_dir, show.name, 'Season %s' % season, video)
#        if destination:
#            print 'move %s -> %s' % (os.path.join(downloads_dir, video), destination)
#            if not DEBUG:
#                try:
#                    os.makedirs(os.path.split(destination)[0])
#                except:
#                    pass
#                move(os.path.join(downloads_dir, video), destination)
#            videos.remove((show, video))
#            Episode.objects.create(season=season, episode=episode, aired=aired, filepath=destination, show=show)
#
#    if len(videos) != 0:
#        print "didn't sort the following:"
#        for x in videos:
#            print '\t', x
#
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

#def find_new_series():
#    for video in find_videos():
#        for season_ep_regex in season_ep_regexs:
#            m = re.match(season_ep_regex, video.lower())
#            if m:
#                break
#        if not m:
#            for date_regex in date_regexs:
#                m = re.match(date_regex, video)
#                if m:
#                    break
#        if m:
#            series_name = canonical_format(m.groupdict()['name'])
#            if tvdb.get_series(series_name):
#                if SuggestedShow.objects.filter(name=series_name).count() == 0 and Show.objects.filter(name=series_name).count() == 0:
#                    SuggestedShow.objects.create(name=series_name)
    
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
    global series_data
    series_data = {} # clear cache

#def do_all():
#    delete_watched_episodes()
#    clean_empty_dirs()
#    clean_episode_db()
#    sort_episodes()
#    fetch_description()
#    find_new_series()
#    refresh_web_gui()

def add_episode(data):
    type, filename, show_name = data[0], data[1], data[2]
    assert type == 'tv show'
    print data

    destination_dir = tv_shows_dir
    aired = None
    episode = 0
    show = Show.objects.get(canonical_name__exact=canonical_format(show_name))
    if isinstance(data[3], datetime):
        aired = data[3]
        season = aired.year
        destination = os.path.join(destination_dir, show.name, 'Season %s' % season, filename)
    else:
        season, episode = data[3]
        destination = os.path.join(destination_dir, show.name, 'Season %s' % int(season), filename)
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

def handle_tv_show_episode(data):
    type, filename, show_name = data[0], data[1], data[2]
    assert type == 'tv show'
    if Show.objects.filter(canonical_name__exact=canonical_format(show_name)).count():
        add_episode(data)
        print 'added episode', data
        return True
    else:
        matches = tvdb.get_series(show_name)
        match = None
        for m in matches:
            if canonical_format(m['name']) == canonical_format(show_name):
                match = m
                break
        if match:
            if not SuggestedShow.objects.filter(name=match['name']).count():
                SuggestedShow.objects.create(name=match['name'])
                print 'found potential new show', match['name']
                return True
        else:
            print 'did not find', show_name, 'on tvdb, ignoring...'
    return False
#if __name__ == '__main__':
#    do_all()
