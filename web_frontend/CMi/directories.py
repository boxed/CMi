import os
from os.path import join, getsize, splitext

try:
    # try OSX
    from Foundation import *
    from AppKit import *
    def send_to_trash(fullpath):
        parts = os.path.split(fullpath)
        NSWorkspace.sharedWorkspace().performFileOperation_source_destination_files_tag_(NSWorkspaceRecycleOperation, parts[0], "", [parts[1]], None)
    tv_shows_dir = os.path.expanduser('~/Downloads/TV Shows')
    movies_dir = os.path.expanduser('~/Downloads/Movies')
    downloads_dir = os.path.expanduser('~/Downloads')
    #tv_shows_dir = '/Volumes/disk/TV Shows'
    #movies_dir = '/Volumes/disk/Movies'
    #downloads_dir = '/Volumes/disk/Downloads'
    print 'OSX...'

except:
    print 'linux...'
    # assume linux
    def send_to_trash(fullpath):
        pass
    tv_shows_dir = os.path.expanduser('/mnt/capsule_disk/TV Shows')
    movies_dir = os.path.expanduser('/mnt/capsule_disk/Movies')
    downloads_dir = os.path.expanduser('/mnt/capsule_disk/Downloads')


SUPPORTED_FILE_FORMATS = set([
                              '.avi',
                              '.mkv',
                              '.m4v',
                              '.mov',
                              '.mp4',
                              ])

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
    movies = []
    for root, dirs, files in os.walk(downloads_dir):
        source_dir = root
        for f in files:
            if supported_extension(f):
                movies.append(f)
        for d in dirs:
            if d in ('Movies', 'TV Shows', 'Incomplete'):
                continue
            if has_videos(os.path.join(root, d)):
                movies.append(d)
        break
    return movies