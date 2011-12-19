import os
from shutil import move
from imdb import IMDb
from CMi.movies.models import *
from CMi.directories import *
ia = IMDb()

def clean(s):
    def first(s, split):
        if split in s:
            s = s.split(split)[0]
        return s
    s = s.lower().replace('.', ' ').strip()
    TAGS = (
        '720p',
        '[',
        '(',
        'bluray',
        'blu-ray',
        'brrip',
        'dvdrip',
        'bdrip',
        'dircut',
    )

    for tag in TAGS:
        s = first(s, tag)
    return s.strip()
    
def simplify_title(t):
    return t.replace(':', '').replace('-', ' ').replace('  ', ' ').strip().lower()

def is_movie(c):
    if c in ('movies', 'tv shows'):
        return (False, c)
    c = simplify_title(c)
    result = dict([(simplify_title(x['title']), x) for x in ia.search_movie(c) if c])
    if c in result:
        return (True, result[c])
    c2 = c.rsplit(' ', 1)[0]
    result = dict([(simplify_title(x['title']), x) for x in ia.search_movie(c2) if c2])
    if c2 in result:
        return (True, result[c2])
    print c, 'was not found on IMDB'
    return (False, None)

def run_movies_cleanup():
    print 'cleaning movie db...'
    if not os.path.exists(movies_dir):
        print 'entire path missing, aborting...'
        return
    for movie in Movie.objects.all():
        if not os.path.exists(movie.filepath):
            movie.delete()

#def do_all():
#    clean_movie_db()
#
#    print 'sorting movies...'
#    movies = find_videos()
#    for root, dirs, files in os.walk(downloads_dir):
#        for f in files:
#            if supported_extension(f):
#                movies.append(f)
#        for d in dirs:
#            if has_videos(os.path.join(root, d)):
#                movies.append(d)
#        break
#    for item in movies:
#        #print clean(item)
#        handle_movie(item)

def handle_movie(data):
    type, filename, name, year = data
    assert type == 'movie'
    m, imdb_info = is_movie(clean(name))
    #print m, imdb_info
    #print imdb_info.keys()
    try:
        os.makedirs(movies_dir)
    except:
        pass
    if m:
        source = os.path.join(downloads_dir, filename)
        destination = os.path.join(movies_dir, filename)
        print 'move', source, '->', destination
        move(source, destination)
        Movie.objects.create(name=imdb_info['title'], filepath=destination, aired=imdb_info['year'])
        return True
    return False