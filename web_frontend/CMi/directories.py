import os

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
