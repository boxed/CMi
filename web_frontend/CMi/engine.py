import os
import re
from CMi.directories import downloads_dir
import datetime

def splitext(s):
    from os.path import splitext as splitext2
    foo = splitext2(s)
    if len(foo) > 1 and len(foo[0]) > len(foo[1]):
        return foo
    return [s, '']

SUPPORTED_FILE_FORMATS = {'.avi', '.mkv', '.m4v', '.mov', '.mp4'}
MINIMUM_FILE_SIZE = 1024 * 1024 * 50 # 50 megabytes

# TV Shows
season_ep_regexs = [
    '(?P<name>.*?) season (?P<season>\d\d?) s? ?(\\2)?ep? ?(?P<episode>\d\d?)',
    '(?P<name>.*?) season (?P<season>\d\d?) episode (?P<episode>\d\d?)',
    '(?P<name>.*[^0-9]) season (?P<season>\d\d?) (\\2)x(?P<episode>\d\d?)',

    '(?P<name>.*?) series (?P<season>\d\d?) s? ?(\\2)?ep? ?(?P<episode>\d\d?)',
    '(?P<name>.*?) series (?P<season>\d\d?) episode (?P<episode>\d\d?)',
    '(?P<name>.*[^0-9]) series (?P<season>\d\d?) (\\2)x(?P<episode>\d\d?)',

    '(?P<name>.*)\s?s ?(?P<season>\d\d?)\s?ep? ?(?P<episode>\d\d?)',
    '(?P<name>.*[^0-9])\s?(?P<season>\d\d?)x(?P<episode>\d\d?)',
]

date_regexs = [
    '(?P<name>.*)(?P<year>\d\d\d\d) (?P<month>\d\d) (?P<day>\d\d)'
]

# Movies
year_regexs = [
    '(?P<name>.*) (?P<year>19\d\d)',
    '(?P<name>.*) (?P<year>20\d\d)',
    '(?P<name>.*) (?P<year>21\d\d)', # Handle stuff until I'm dead at least :P

     # Some pseudo-matches to handle common suffixes
    '(?P<name>.*) dvdrip(?P<year>)',
    '(?P<name>.*) bluray(?P<year>)',
    '(?P<name>.*) xvid(?P<year>)',
]

def supported_extension(s):
    extension = splitext(s)[1]
    return extension in SUPPORTED_FILE_FORMATS

def has_videos(directory):
    for root, dirs, files in os.walk(directory):
        count = 0
        for f in files:
            if supported_extension(f):
                # Used to have an extra check that the filename of the video file and the name of the directory had to match:
                #   and os.path.split(directory)[-1] in f:
                count += 1
        if count == 1:
            return True
        break
    return False

def find_videos():
    videos = []
    for root, dirs, files in os.walk(downloads_dir):
        for d in dirs[:]:
            if d.lower() in ('movies', 'tv shows', 'incomplete', 'sample'):
                dirs.remove(d)
                continue
        ## This code is for supporting directories with a good name with a badly named file in them. Disabled for now since this doesn't seem to be common anymore
        #     full_path = os.path.join(root, d)
        #     if has_videos(full_path):
        #         # print 'handle %s as dir' % full_path
        #         videos.append(full_path[len(downloads_dir)+1:])
        #         dirs.remove(d)
        #         continue
        for f in files:
            if supported_extension(f):
                full_path = os.path.join(root, f)
                if playable_path(full_path):
                    videos.append(full_path[len(downloads_dir)+1:])
                # print 'handle %s as file' % full_path
    return videos

def playable_path(path):
    if os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            if 'sample' in root.lower():
                continue
            for f in files:
                if 'sample' in f.lower():
                    continue
                if os.path.getsize(os.path.join(root, f)) < MINIMUM_FILE_SIZE:
                    continue
                extension = os.path.splitext(f)[1]
                if extension in SUPPORTED_FILE_FORMATS:
                    path = os.path.join(root, f)
                    break
    return path

def canonical_format(s):
    s2 = s.lower()
    remove_regexes = [
        r'^\[[^\]]*\]',
        r'^\([^\)]*\)',
        r'^www\.[a-z]+\.[a-z]{2,3}',
        r"'",
    ]
    s2 = re.sub('|'.join(remove_regexes), '', s2)

    replace_with_space_literals = ['\\%s' % x for x in '/._-:()[]'] + [' 720p ?', ' 1080p ?', ' x264 ?']
    s2 = re.sub('|'.join(replace_with_space_literals), ' ', s2)

    s2 = s2.replace('&', 'and') # standardize on "and"
    s2 = re.sub(r' +', ' ', s2).strip() # remove duplicate spaces
    replace_list = {
        'the daily show with jon stewart': 'the daily show',
        'marvels agents of s h i e l d': 'marvels agents of shield',
        'cosmos a spacetime odyssey': 'cosmos a space time odyssey',
        'stargate sg1': 'stargate sg-1',
        'stargate sg 1': 'stargate sg-1',
    }
    if s2 in replace_list:
        s2 = replace_list[s2]
    return s2

def match_file(filename):
    global season_ep_regexs
    global date_regexs
    global year_regexs
    if '/' in filename:
        for part in xrange(filename.count('/')):
            x = filename.rsplit('/', part+1)[-1]
            result = match_video(x, canonical_format(splitext(x)[0]))
            if result[0] != 'movie_fallback':
                return result[0], filename, result[2], result[3]

    result = match_video(filename, canonical_format(splitext(filename)[0]))
    if result[0] == 'movie_fallback':
        return 'movie', result[1], result[2], result[3]
    return result

def match_video(filename, video):
    #print video
    m = None
    for date_regex in date_regexs:
        m = re.match(date_regex, video)
        if m:
            #print 'matched date regex:', date_regex
            break
    if m:
        name, aired = canonical_format(m.groupdict()['name']), datetime.datetime(int(m.groupdict()['year']), int(m.groupdict()['month']), int(m.groupdict()['day']))
        if name:
            return 'tv show', filename, name, aired

    for season_ep_regex in season_ep_regexs:
        m = re.match(season_ep_regex, video)
        if m:
            #print 'matched season ep regex:', date_regex
            break
    if m:
        name, season, episode = canonical_format(m.groupdict()['name']), m.groupdict()['season'], m.groupdict()['episode']
        if name:
            return 'tv show', filename, name, (int(season), int(episode))

    for year_regex in year_regexs:
        m = re.match(year_regex, video)
        if m:
            #print 'matched year regex:', date_regex
            break
    if m:
        return 'movie', filename, canonical_format(m.groupdict()['name']), int(m.groupdict()['year'] or 0)
    #print 'matched nothing, defaulting'

    return 'movie_fallback', filename, canonical_format(filename), 0
