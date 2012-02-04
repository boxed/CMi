from shutil import move
from CMi.engine import canonical_format
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

is_not_movie_cache = set()
def is_movie(c):
    if c in ('movies', 'tv shows'):
        return False, c
    c = canonical_format(c)
    if c in is_not_movie_cache:
        return False, c
    result = dict([(canonical_format(x['title']), x) for x in ia.search_movie(c) if c])
    if c in result:
        return True, result[c]
    c2 = canonical_format(c.rsplit(' ', 1)[0])
    result = dict([(canonical_format(x['title']), x) for x in ia.search_movie(c2) if c2])
    if c2 in result:
        return True, result[c2]
    # We should also check x['akas'] if available for alternative titles. Example: 'A Separation::International (English title) (imdb display title)'
    print c, 'was not found on IMDB'
    is_not_movie_cache.add(c)
    return False, None

def run_movies_cleanup():
    #print 'cleaning movie db...'
    if not os.path.exists(movies_dir):
        print 'run_movies_cleanup: entire path missing, aborting...'
        return
    for movie in Movie.objects.all():
        if not os.path.exists(movie.filepath):
            movie.delete()

def handle_movie(data):
    print data
    type, filename, name, year = data
    assert type == 'movie'
    m, imdb_info = is_movie(clean(name))
    if m:
        try:
            os.makedirs(movies_dir)
        except:
            pass
        source = os.path.join(downloads_dir, filename)
        destination = os.path.join(movies_dir, filename)
        print 'move', source, '->', destination
        move(source, destination)
        year = imdb_info['year'] if 'year' in imdb_info else ''
        Movie.objects.create(name=imdb_info['title'], filepath=destination, aired=year)
        return True
    return False