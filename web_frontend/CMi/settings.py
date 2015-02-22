# Django settings for CMi project.
import os
import sys
import shutil

DEBUG = True
TEMPLATE_DEBUG = DEBUG

ADMINS = (
    # ('Your Name', 'your_email@domain.com'),
    ('Anders', 'boxed@killingar.net')
)

MANAGERS = ADMINS

support_folder = os.path.expanduser('~/Library/Application Support/CMi/')
if not os.path.exists(support_folder):
    print 'creating dir:', support_folder
    os.makedirs(support_folder)
if not os.path.exists(support_folder+'cmi.db') and os.path.exists(os.getcwd()+'/CMi/cmi.db'):
    print 'copying db file...'
    shutil.copyfile(os.getcwd()+'/CMi/cmi.db', support_folder+'cmi.db')

plugin_path = os.path.join(support_folder, 'plugins')
sys.path.insert(0, plugin_path)
print 'Added folder %s to path' % plugin_path

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3', # Add 'postgresql_psycopg2', 'postgresql', 'mysql', 'sqlite3' or 'oracle'.
        'NAME': support_folder+'cmi.db',                      # Or path to database file if using sqlite3.
        'USER': '',                      # Not used with sqlite3.
        'PASSWORD': '',                  # Not used with sqlite3.
        'HOST': '',                      # Set to empty string for localhost. Not used with sqlite3.
        'PORT': '',                      # Set to empty string for default. Not used with sqlite3.
    }
}

#import socket
#if socket.gethostname() == 'Jizo.local':
#   DATABASES['default']['NAME'] = 'cmi.jizo.db'

# Local time zone for this installation. Choices can be found here:
# http://en.wikipedia.org/wiki/List_of_tz_zones_by_name
# although not all choices may be available on all operating systems.
# If running in a Windows environment this must be set to the same as your
# system time zone.
TIME_ZONE = None

# Language code for this installation. All choices can be found here:
# http://www.i18nguy.com/unicode/language-identifiers.html
LANGUAGE_CODE = 'en-us'

SITE_ID = 1

# If you set this to False, Django will make some optimizations so as not
# to load the internationalization machinery.
USE_I18N = True

# Absolute path to the directory that holds media.
# Example: "/home/media/media.lawrence.com/"
MEDIA_ROOT = os.path.abspath(os.path.join(os.path.split(__file__)[0], 'media'))

# URL that handles the media served from MEDIA_ROOT. Make sure to use a
# trailing slash if there is a path component (optional in other cases).
# Examples: "http://media.lawrence.com", "http://example.com/media/"
MEDIA_URL = ''

# URL prefix for admin media -- CSS, JavaScript and images. Make sure to use a
# trailing slash.
# Examples: "http://foo.com/media/", "/media/".
ADMIN_MEDIA_PREFIX = '/media/'
STATIC_ROOT = '/media/'
STATIC_URL = '/media/'

# Make this unique, and don't share it with anybody.
SECRET_KEY = '@wb(e#@u4vdu*9!+0%0&zimpzud)-x)-+71)*vrgo+jak2&k1n'

# List of callables that know how to import templates from various sources.
TEMPLATE_LOADERS = (
    'django.template.loaders.filesystem.Loader',
    'django.template.loaders.app_directories.Loader',
#     'django.template.loaders.eggs.Loader',
)

TEMPLATE_CONTEXT_PROCESSORS = (
    'django.contrib.auth.context_processors.auth',
    'django.contrib.messages.context_processors.messages',
    'CMi.context_processors.ajax',
)

MIDDLEWARE_CLASSES = (
    'django.middleware.common.CommonMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'CMi.StartupMiddleware',
)

ROOT_URLCONF = 'CMi.urls'

TEMPLATE_DIRS = (
    # Put strings here, like "/home/html/django_templates" or "C:/www/django/templates".
    # Always use forward slashes, even on Windows.
    # Don't forget to use absolute paths, not relative paths.
    #'/Users/boxed/Projects/CMi/templates'
    os.path.abspath(os.path.join(os.path.split(__file__)[0], 'templates')),
)

plugins = []
for root, dirs, files in os.walk(os.path.join(support_folder, 'plugins')):
    plugins = [x for x in dirs if not x.startswith('.')]
    break

INSTALLED_APPS = (
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.sites',
    'django.contrib.messages',
    'django.contrib.admin',
    'CMi.base',
    'CMi.tvshows',
    'CMi.movies',
    'CMi.cal',
    'CMi.filesystem',
    'CMi.weather',
)+tuple(plugins)

CODE_CHANGED = 1
