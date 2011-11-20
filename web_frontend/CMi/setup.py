from setuptools import setup

APP = ['__init__.py']
OPTIONS = {
    'argv_emulation': False, 
    'includes': [
        'django', 
        'django.core.management.commands.cleanup',
        'django.core.management.commands.compilemessages',
        'django.core.management.commands.createcachetable',
        'django.core.management.commands.dbshell',
        'django.core.management.commands.diffsettings',
        'django.core.management.commands.dumpdata',
        'django.core.management.commands.flush',
        'django.core.management.commands.inspectdb',
        'django.core.management.commands.loaddata',
        'django.core.management.commands.makemessages',
        'django.core.management.commands.reset',
        'django.core.management.commands.runfcgi',
        'django.core.management.commands.runserver',
        'django.core.management.commands.shell',
        'django.core.management.commands.sql',
        'django.core.management.commands.sqlreset',
        'django.core.management.commands.startapp',
        'django.core.management.commands.syncdb',
        'django.core.management.commands.test',
        'django.core.management.commands.testserver',
    ],
}

setup(
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)