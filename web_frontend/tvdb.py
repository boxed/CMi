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


from datetime import datetime
from io import BytesIO
from urllib.parse import quote
from urllib.request import urlopen
from xml.etree import ElementTree
from zipfile import ZipFile

API_KEY = "1645288C00EAD78F"

_LANGUAGE = "en"


BASE_URL = "https://www.thetvdb.com/"

# Internal Utility Functions.
def _s2date(s):
    """Convert a string representation of a date into a datetime object."""
    y,m,d = s.split("-")
    return datetime(int(y), int(m), int(d))

def _g(node, tag_name, wrapper_func=str, default=None):
    """Extract the value from the child tag named tag_name (case insensitive)."""
    for child in node:
        if child.tag.lower() == tag_name:
            if child.text:
                return wrapper_func(child.text)
            break
    return default

def _findall(node, tag_name):
    return [x for x in node if x.tag.lower() == tag_name]

def _parse_series(node):
    """Parse a series listing, return a dict."""
    return dict(id=_g(node, 'id', int),
                language=_g(node, 'language'),
                name=_g(node, 'seriesname'),
                overview=_g(node, 'overview'),
                first_aired=_g(node, 'firstaired', _s2date),
                imdb_id=_g(node, 'imdb_id'),
                status=_g(node, 'status'))

def _parse_episode(node):
    """Parse an episode listing. Return a dict"""
    return dict(id=_g(node, 'id', int),
                name=_g(node, 'episodename'),
                episode_number=_g(node, 'episodenumber', int),
                first_aired=_g(node, 'firstaired', _s2date),
                overview=_g(node, 'overview'),
                season_number=_g(node, 'seasonnumber', int))


# Official API Starts here.

def get_series(series_name_search):
    """Return all possible matches for series_name_search in the chosen language"""
    url = "%sapi/GetSeries.php?seriesname=%s&language=%s" % (BASE_URL, quote(series_name_search), _LANGUAGE)
    root = ElementTree.parse(urlopen(url)).getroot()
    return [_parse_series(x) for x in _findall(root, 'series')]

def get_series_all(series_id):
    """Return all available data for a series, including episodes."""
    url = "%sapi/%s/series/%s/all/%s.zip" % (BASE_URL, API_KEY, series_id, _LANGUAGE)
    zf = ZipFile(BytesIO(urlopen(url).read()))
    root = ElementTree.fromstring(zf.read("%s.xml" % (_LANGUAGE, )))
    series = _parse_series(_findall(root, 'series')[0])
    series['episodes'] = [_parse_episode(e) for e in _findall(root, 'episode')]
    return series
