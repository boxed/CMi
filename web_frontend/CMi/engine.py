import os
import re
from os.path import join, getsize, splitext
from CMi.directories import downloads_dir
import datetime

SUPPORTED_FILE_FORMATS = set([
                              '.avi',
                              '.mkv',
                              '.m4v',
                              '.mov',
                              '.mp4',
                              '.rar',
                              ])

# TV Shows
season_ep_regexs = [
                    '(?P<name>.*)s(?P<season>\d\d)e(?P<episode>\d\d?)',
                    '(?P<name>.*[^0-9])(?P<season>\d\d?)x(?P<episode>\d\d?)',
                    '(?P<name>.*[^0-9])(?P<season>\d\d?)(?P<episode>\d\d)',
                    ]
date_regexs = [
               '(?P<name>.*)(?P<year>\d\d\d\d) (?P<month>\d\d) (?P<day>\d\d)'
               ]

# Movies
year_regexs = [
    '(?P<name>.*)(?P<year>19\d\d)',
    '(?P<name>.*)(?P<year>20\d\d)',
    '(?P<name>.*)(?P<year>21\d\d)', # Handle stuff until I'm dead at least :P

     # Some pseudo-matches to handle common suffixes
    '(?P<name>.*) dvdrip(?P<year>)',
    '(?P<name>.*) bluray(?P<year>)',
]

def supported_extension(s):
    extension = splitext(s)[1]
    return extension in SUPPORTED_FILE_FORMATS

def has_videos(directory):
    for root, dirs, files in os.walk(directory):
        for f in files:
            if supported_extension(f):
                return True
        break
    return False

def find_videos():
    videos = []
    for root, dirs, files in os.walk(downloads_dir):
        for f in files:
            if supported_extension(f):
                videos.append(f)
        for d in dirs:
            if d.lower() in ('movies', 'tv shows', 'incomplete'):
                continue
            if has_videos(os.path.join(root, d)):
                videos.append(d)
        break
    print 'found', videos
    return videos

def playable_path(path):
    if os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            if 'sample' in root.lower():
                continue
            for f in files:
                if 'sample' in f.lower():
                    continue
                extension = os.path.splitext(f)[1]
                if extension in SUPPORTED_FILE_FORMATS:
                    path = os.path.join(root, f)
                    break
    return path

def refresh_web_gui():
    import subprocess
    subprocess.call(['open', 'CMiVideoPlayer://refresh'])
    print 'refresh GUI command sent'

def canonical_format(s):
    s2 = re.sub(r'^\[[^\]]*\]', '', s)
    s2 = re.sub(r'^\([^\)]*\)', '', s2)
    s2 = s2.lower().replace('.', ' ').replace('_', ' ').replace('-', ' ')
    s2 = s2.replace('&', 'and').replace("'", '').replace(' 720p ', ' ').replace(' 1080p ', ' ').replace(' x264 ', ' ')
    s2 = s2.replace('(', ' ').replace(')', ' ').replace('[', ' ').replace(']', ' ')
    s2 = re.sub(r' +', ' ', s2).strip()
    replace_list = {
        'the daily show with jon stewart': 'the daily show'
    }
    if s2 in replace_list:
        s2 = replace_list[s2]
    return s2

def match_file(filename):
    global season_ep_regexs
    global date_regexs
    global year_regexs
    video = canonical_format(filename)
    m = None
    for date_regex in date_regexs:
        m = re.match(date_regex, video)
        if m:
            break
    if m:
        name, aired = canonical_format(m.groupdict()['name']), datetime.datetime(int(m.groupdict()['year']), int(m.groupdict()['month']), int(m.groupdict()['day']))
        return 'tv show', filename, name, aired

    for year_regex in year_regexs:
        m = re.match(year_regex, video.lower())
        if m:
            break
    if m:
        return 'movie', filename, canonical_format(m.groupdict()['name']), int(m.groupdict()['year'] or 0)

    for season_ep_regex in season_ep_regexs:
        m = re.match(season_ep_regex, video.lower())
        if m:
            break
    if m:
        name, season, episode = canonical_format(m.groupdict()['name']), m.groupdict()['season'], m.groupdict()['episode']
        return 'tv show', filename, name, (season, episode)
    print filename, 'matched nothing, ignoring...'
    return None