# Django settings for CMi project.
import os
import sys
import shutil

DEBUG = True

ADMINS = (
    ('Anders', 'boxed@killingar.net'),
)

MANAGERS = ADMINS

# CMI_SUPPORT_FOLDER lets you run against a different database and plugin folder, e.g. for testing
support_folder = os.environ.get('CMI_SUPPORT_FOLDER', os.path.expanduser('~/Library/Application Support/CMi/'))
SUPPORT_FOLDER = support_folder
if not os.path.exists(support_folder):
    print('creating dir:', support_folder)
    os.makedirs(support_folder)
if not os.path.exists(os.path.join(support_folder, 'cmi.db')) and os.path.exists(os.getcwd()+'/CMi/cmi.db'):
    print('copying db file...')
    shutil.copyfile(os.getcwd()+'/CMi/cmi.db', os.path.join(support_folder, 'cmi.db'))

plugin_path = os.path.join(support_folder, 'plugins')
sys.path.insert(0, plugin_path)
print('Added folder %s to path' % plugin_path)

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.path.join(support_folder, 'cmi.db'),
    }
}

DEFAULT_AUTO_FIELD = 'django.db.models.AutoField'

ALLOWED_HOSTS = ['*']

# Use the system time zone, e.g. /etc/localtime -> /var/db/timezone/zoneinfo/Europe/Stockholm
TIME_ZONE = os.path.realpath('/etc/localtime').split('zoneinfo/')[-1] if 'zoneinfo/' in os.path.realpath('/etc/localtime') else 'UTC'
USE_TZ = False

LANGUAGE_CODE = 'en-us'

USE_I18N = True

# Absolute path to the directory that holds media.
MEDIA_ROOT = os.path.abspath(os.path.join(os.path.split(__file__)[0], 'media'))

STATIC_URL = '/static/'

# Make this unique, and don't share it with anybody.
SECRET_KEY = '@wb(e#@u4vdu*9!+0%0&zimpzud)-x)-+71)*vrgo+jak2&k1n'

PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.PBKDF2PasswordHasher',
    'CMi.hashers.LegacySHA1PasswordHasher',
]

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [os.path.abspath(os.path.join(os.path.split(__file__)[0], 'templates'))],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'CMi.context_processors.ajax',
            ],
        },
    },
]

MIDDLEWARE = (
    'django.middleware.common.CommonMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
)

ROOT_URLCONF = 'CMi.urls'

plugins = []
for root, dirs, files in os.walk(os.path.join(support_folder, 'plugins')):
    plugins = [x for x in dirs if not x.startswith('.')]
    break

INSTALLED_APPS = (
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'django.contrib.admin',
    'CMi.base',
    'CMi.tvshows',
    'CMi.movies',
    'CMi.cal',
    'CMi.filesystem',
    'CMi.weather',
    'CMi.plex',
)+tuple(plugins)

CODE_CHANGED = 1
