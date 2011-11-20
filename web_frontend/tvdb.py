"""PyTVDB is a python interface to TheTVDB.com's web API.
Copyright (c) 2009, Andre LeBlanc <andrepleblanc@gmail.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the <organization> nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY <copyright holder> ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <copyright holder> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"""


from BeautifulSoup import BeautifulStoneSoup
from datetime import datetime
from zipfile import ZipFile
import urllib, urllib2
import time
import random

API_KEY = "1645288C00EAD78F"

_LANGUAGE = "en"


BASE_URL = "http://www.thetvdb.com/"
ONE_DAY = 86400 #seconds.

# Internal Utility Functions.
def _s2date(s):
    """Convert a string representation of a date into a datetime object."""
    y,m,d = s.split("-")
    return datetime(int(y), int(m), int(d))

def _g(soup, tag_name, wrapper_func=None, default=None):
    """Extract the value from the tag named tag_name."""
    if not wrapper_func:
        wrapper_func = unicode
    node = soup.find(tag_name)
    if node and node.contents:
        return wrapper_func(node.contents[0])
    else:
        return default

def _parse_partial_series(soup):
    """Parse partial series soup (from search results), return a dict."""
    s = dict(id=_g(soup, 'id', int),
             language=_g(soup, 'language'),
             name=_g(soup, 'seriesname'),
             banner=_g(soup, 'banner'),
             overview=_g(soup, 'overview'),
             first_aired=_g(soup, 'first_aired', _s2date),
             imdb_id=_g(soup, 'imdb_id'),
             zap2it_id=_g(soup, 'zap2it_id'))
    return s

def _parse_series(soup):
    """Parse a complete series listing."""
    s = _parse_partial_series(soup)
    s.update(dict(airs_days=_g(soup, "airs_dayofweek"),
                  airs_time=_g(soup, "airs_time"),
                  content_rating=_g(soup, "contentrating"),
                  genre=_g(soup, "genre", lambda genre: [g for g in genre.split("|") if g]),
                  network=_g(soup, 'network'),
                  rating=_g(soup, 'rating'),
                  runtime=_g(soup, 'runtime'),
                  status=_g(soup, 'status'),
                  fanart=_g(soup, 'fanart'),
                  last_updated=_g(soup, 'lastupdated', int),
                  poster=_g(soup, 'poster')))
    return s

def _parse_episode(soup):
    """Parse an episode listing. Return a dict"""
    e = dict(id=_g(soup, 'id', int),
             combined_episode_number=_g(soup, 'combined_episodenumber'),
             combined_season=_g(soup, 'combined_season', int),
             dvd_chapter=_g(soup, 'dvd_chapter', int),
             dvd_disc_id=_g(soup, 'dvd_discid'),             
             dvd_episode_number=_g(soup, 'dvd_episodenumber'),
             dvd_season=_g(soup, 'dvd_season', int),
             director=_g(soup, 'director'),
             name=_g(soup, 'episodename'),
             episode_number=_g(soup, 'episodenumber', int),
             first_aired=_g(soup, 'firstaired', _s2date),
             gueststars=_g(soup, 'gueststars', lambda stars: [s for s in stars.split("|") if s]),
             imdb_id=_g(soup, 'imdb_id'),
             language=_g(soup, 'language'),
             overview=_g(soup, 'overview'),
             production_code=_g(soup, 'productioncode'),
             rating=_g(soup, 'rating'),
             season_number=_g(soup, 'seasonnumber', int),
             writer=_g(soup, 'writer'),
             absolute_number=_g(soup, 'absolute_number', int),
             airs_after_season=_g(soup, 'airsafter_season', int),
             airs_before_episode=_g(soup, 'airsbefore_episode', int),
             airs_before_season=_g(soup, 'airsbefore_season', int),
             last_updated=_g(soup, 'lastupdated', int),
             season_id=_g(soup, 'seasonid', int),
             image_flag=_g(soup, 'epimgflag', int),
             image=_g(soup, 'filename'))
    return e

def _parse_actor(soup):
    """Parse an Actor, return a dict"""
    a = dict(id=_g(soup, 'id', int),
             image=_g(soup, 'image'),
             name=_g(soup, 'name'),
             role=_g(soup, 'role'),
             sort_order=_g(soup, 'sortorder', int))
    return a

def _parse_banner(soup):
    """Parse a banner, return a dict"""
    b = dict(id=_g(soup, 'id', int),
             path=_g(soup, 'bannerpath'),
             type=_g(soup, 'bannertype'),
             type2=_g(soup, 'bannertype2'),
             colors=_g(soup, 'colors', lambda cstr: [tuple([int(i) for i in c.split(",")]) for c in cstr.split("|") if c]),
             language=_g(soup, 'language'),
             thumbnail_path=_g(soup, 'thumbnailpath'),
             vignette_path=_g(soup, 'vignettepath'))
    if 'season' in (b['type'], b['type2']):
        b['season'] = _g(soup, 'season', int)
        
    return b
             
             

# Official API Starts here.

def get_languages():
    """Return a list of languages supported by the server

    Returns a list of dicts each having 'name', 'abbreviation', 
    and 'id' keys.
    
    """
    url = "%s/api/%s/languages.xml" % (BASE_URL, API_KEY)
    soup = BeautifulStoneSoup(urllib2.urlopen(url).read())
    languages = []
    for lang in soup.languages.findAll("language"):
        languages.append({'name': _g(lang, 'name'),
                          'abbreviation': _g(lang, 'abbreviation'),
                          'id': _g(lang, 'id', int)})
    return languages


def set_language(language_abbr):
    """Set the language to be used for all future queries"""
    _LANGUAGE = language_abbr
    

def get_series(series_name_search):
    """Return all possible matches for series_name_search in the chosen language
    
    
    """
    url = "%sapi/GetSeries.php?seriesname=%s&language=%s" % (BASE_URL, urllib.quote(series_name_search), _LANGUAGE)
    soup = BeautifulStoneSoup(urllib2.urlopen(url).read())
    matches = []
    for series in soup.data.findAll("series"):
        matches.append(_parse_series(series))
    return matches

def get_series_details(series_id):
    """Returns details on a single series, not including banners/episodes)"""
    url = "%sapi/%s/series/%s/%s.xml" % (BASE_URL, API_KEY, series_id, _LANGUAGE)    
    soup = BeautifulStoneSoup(urllib2.urlopen(url).read())
    return _parse_series(soup.data)

def get_episode(episode_id):
    """Returns details on a single episode"""
    url = "%sapi/%s/episodes/%s/%s.xml" % (BASE_URL, API_KEY, episode_id, _LANGUAGE)    
    soup = BeautifulStoneSoup(urllib2.urlopen(url).read())
    return _parse_episode(soup.data)
    
    

def get_series_all(series_id, episodes=True, banners=True, actors=True):
    """Return all available data for a series."""
    url = "%sapi/%s/series/%s/all/%s.zip" % (BASE_URL, API_KEY, series_id, _LANGUAGE)
    filename, headers = urllib.urlretrieve(url)
    zf = ZipFile(file(filename))
    soup = BeautifulStoneSoup(zf.read("%s.xml" % (_LANGUAGE, )))
    series = _parse_series(soup.find('series'))
    if episodes:
        series['episodes'] = [_parse_episode(e) for e in soup.findAll('episode')]
    
    if actors:
        soup = BeautifulStoneSoup(zf.read("actors.xml"))
        series['actors'] = [_parse_actor(a) for a in soup.findAll('actor')]

    if banners:
        soup = BeautifulStoneSoup(zf.read("banners.xml"))
        series['banners'] = [_parse_banner(b) for b in soup.findAll('banner')]

    return series

def get_updates(since, for_series_ids=None):
    """Returns  all updates since 'since'. optionally filtering on series id"""
    if isinstance(since, datetime):
        since = time.mktime(since.timetuple())

    now = time.time()
    if since - now > ONE_DAY * 30:
        interval = 'all'
    elif since - now > ONE_DAY * 7:
        interval = 'month'
    elif since - now > ONE_DAY:
        interval = 'week'
    else:
        interval = 'day'
        
    url = "%sapi/%s/updates/updates_%s.zip" % (BASE_URL, API_KEY, interval)
    filename, headers = urllib.urlretrieve(url)
    zf = ZipFile(file(filename))
    soup = BeautifulStoneSoup(zf.read('updates_%s.xml' % (interval,)))
    last_update = int(soup.data['time'])
    soup = soup.data
    def _parse_series_update(soup):
        d = dict(id=_g(soup, 'id', int),
                 time=_g(soup, 'time', int))
        if d['time'] > since and (for_series_ids is None or d['id'] in for_series_ids):
            return d
        return None
    def _parse_episode_update(soup):
        d = dict(id=_g(soup, 'id', int),
                 series=_g(soup, 'series', int),
                 time=_g(soup, 'time', int))
        if d['time'] > since and (for_series_ids is None or d['series'] in for_series_ids):
            return d
        return None
    def _parse_banner_update(soup):
        d = dict(series=_g(soup, 'series', int),
                    format=_g(soup, 'format'),
                    language=_g(soup, 'language'),
                    time=_g(soup, 'time', int),
                    path=_g(soup, 'path'),
                    type=_g(soup, 'type'))
        if d['time'] > since and (for_series_ids is None or d['series'] in for_series_ids):
            return d
        return None
    def _for_series(id):
        return for_series_ids is None or id in for_series_ids

    return dict(series=filter(None, [_parse_series_update(s) for s in soup.findAll('series', recursive=False)]),
                banners=filter(None, [_parse_banner_update(b) for b in soup.findAll('banner', recursive=False)]),
                episodes=filter(None, [_parse_episode_update(e) for e in soup.findAll('episode', recursive=False)]))
    
    
    

# Tests
if __name__ == '__main__':
    import unittest
    class TestSequenceFunctions(unittest.TestCase):

        def setUp(self):
            self.soup = BeautifulStoneSoup("""
            <?xml version="1.0" encoding="UTF-8" ?>
            <Data>
             <Series>
              <id>74302</id>
              <Actors>|Matt Berry|Dave Brown|Julian Barratt|Michael Fielding|Noel Fielding|Rich Fulcher|Victoria Wicks|</Actors>
              <Airs_DayOfWeek></Airs_DayOfWeek>
              <Airs_Time></Airs_Time>
              <ContentRating></ContentRating>
              <FirstAired>2003-05-01</FirstAired>
            
              <Genre>|Comedy|</Genre>
              <IMDB_ID>tt0416394</IMDB_ID>
              <Language>en</Language>
              <Network>BBC-3</Network>
              <Overview>Welcome to The Mighty Boosh guide. Come with us now on a journey through time and space... to the world of The Mighty Boosh... Written by and starring Noel Fielding and Julian Barratt, The Mighty Boosh is an off-the-wall adventure based on their Perrier Award-winning comedy show. The Mighty Boosh is a show about two zoo keepers, Howard Moon and Vince Noir, who work at &quot;The Zoo-niverse&quot;, a dilapidated but magical zoo. It is run by Bob Fossil, a demented American with a military disposition. Vince is a regular 'Mowgli in flares', due to his affinity with animals and adoration for all things Seventies. Howard likes to think he is more the brains of their zoo-keeping outfit, destined for better things. Each week they get involved in a different adventure. Whether they end up in the Arctic tundra or monkey hell they somehow always manage to get back to the zoo intact...</Overview>
            
              <Rating>6.4</Rating>
              <Runtime>30</Runtime>
              <SeriesID>26324</SeriesID>
              <SeriesName>The Mighty Boosh</SeriesName>
              <Status>Continuing</Status>
              <added></added>
            
              <addedBy></addedBy>
              <banner>graphical/74302-g2.jpg</banner>
              <fanart>fanart/original/74302-1.jpg</fanart>
              <lastupdated>1231841310</lastupdated>
              <poster>posters/74302-1.jpg</poster>
              <zap2it_id></zap2it_id>
            </Series>
            
            <Episode>
              <id>336067</id>
              <Combined_episodenumber>1</Combined_episodenumber>
              <Combined_season>0</Combined_season>
              <DVD_chapter></DVD_chapter>
              <DVD_discid></DVD_discid>
              <DVD_episodenumber></DVD_episodenumber>
              <DVD_season></DVD_season>
            
              <Director></Director>
              <EpImgFlag>1</EpImgFlag>
              <EpisodeName>Tundra (Pilot)</EpisodeName>
              <EpisodeNumber>1</EpisodeNumber>
              <FirstAired>2003-05-20</FirstAired>
              <GuestStars></GuestStars>
              <IMDB_ID></IMDB_ID>
            
              <Language>en</Language>
              <Overview>Pilot Episode: Howard Moon and Vince Noir are keepers at the Zoo-niverse but are not happy with their lot - particularly when new employee Dixon Bainbridge is immediately put on a pedestal by owner Bob Fossil due to his adventures and impressive moustache. Keen to show he is more than a match for Bainbridge, Howard takes Vince on a dangerous mission to be the first to recover a mysterious jewel deep in the frozen tundra of the Artic.</Overview>
              <ProductionCode></ProductionCode>
              <Rating></Rating>
              <SeasonNumber>0</SeasonNumber>
              <Writer></Writer>
              <absolute_number></absolute_number>
            
              <airsafter_season></airsafter_season>
              <airsbefore_episode>1</airsbefore_episode>
              <airsbefore_season>1</airsbefore_season>
              <filename>episodes/74302-336067.jpg</filename>
              <lastupdated>1217143944</lastupdated>
              <seasonid>21764</seasonid>
              <seriesid>74302</seriesid>
            </Episode>
           </Data>""")
        
        def test_parse_series(self):
            correct = {'airs_days': None,
                       'airs_time': None,
                       'banner': u'graphical/74302-g2.jpg',
                       'content_rating': None,
                       'fanart': u'fanart/original/74302-1.jpg',
                       'first_aired': None,
                       'genre': [u'Comedy'],
                       'id': 74302,
                       'imdb_id': u'tt0416394',
                       'language': u'en',
                       'last_updated': 1231841310,
                       'name': u'The Mighty Boosh',
                       'network': u'BBC-3',
                       'overview': u"Welcome to The Mighty Boosh guide. Come with us now on a journey through time and space... to the world of The Mighty Boosh... Written by and starring Noel Fielding and Julian Barratt, The Mighty Boosh is an off-the-wall adventure based on their Perrier Award-winning comedy show. The Mighty Boosh is a show about two zoo keepers, Howard Moon and Vince Noir, who work at &quot;The Zoo-niverse&quot;, a dilapidated but magical zoo. It is run by Bob Fossil, a demented American with a military disposition. Vince is a regular 'Mowgli in flares', due to his affinity with animals and adoration for all things Seventies. Howard likes to think he is more the brains of their zoo-keeping outfit, destined for better things. Each week they get involved in a different adventure. Whether they end up in the Arctic tundra or monkey hell they somehow always manage to get back to the zoo intact...",
                       'poster': u'posters/74302-1.jpg',
                       'rating': u'6.4',
                       'runtime': u'30',
                       'status': u'Continuing',
                       'zap2it_id': None}
            self.assertEqual(correct, _parse_series(self.soup.data.find('series', recursive=False)))
            
        def test_parse_epside(self):
            correct = {'absolute_number': None,
                       'airs_after_season': None,
                       'airs_before_episode': 1,
                       'airs_before_season': 1,
                       'combined_episode_number': 1,
                       'combined_season': 0,
                       'director': None,
                       'dvd_chapter': None,
                       'dvd_disc_id': None,
                       'dvd_episode_number': None,
                       'dvd_season': None,
                       'episode_number': 1,
                       'first_aired': datetime(2003, 5, 20, 0, 0),
                       'gueststars': None,
                       'id': 336067,
                       'image': u'episodes/74302-336067.jpg',
                       'image_flag': 1,
                       'imdb_id': None,
                       'language': u'en',
                       'last_updated': 1217143944,
                       'name': u'Tundra (Pilot)',
                       'overview': u'Pilot Episode: Howard Moon and Vince Noir are keepers at the Zoo-niverse but are not happy with their lot - particularly when new employee Dixon Bainbridge is immediately put on a pedestal by owner Bob Fossil due to his adventures and impressive moustache. Keen to show he is more than a match for Bainbridge, Howard takes Vince on a dangerous mission to be the first to recover a mysterious jewel deep in the frozen tundra of the Artic.',
                       'production_code': None,
                       'rating': None,
                       'season_id': 21764,
                       'season_number': 0,
                       'writer': None}

            self.assertEqual(correct, _parse_episode(self.soup.data.find("episode", recursive=False)))
            pass
    unittest.main()
