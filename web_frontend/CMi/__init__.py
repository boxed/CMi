if __name__ == '__main__':
    # Monkey patch import_module so as to not try site-packages.py
    from django import utils as du
    def import_module(name, package=None):
        """Import a module.
    
        The 'package' argument is required when performing a relative import. It
        specifies the package to use as the anchor point from which to resolve the
        relative import to an absolute import.
    
        """
        if '.zip' in name:
            return sys.modules[name]
        if name.startswith('.'):
            if not package:
                raise TypeError("relative imports require the 'package' argument")
            level = 0
            for character in name:
                if character != '.':
                    break
                level += 1
            name = _resolve_name(name[level:], package, level)
        __import__(name)
        return sys.modules[name]
    du.import_module = import_module

    from django.core.management import setup_environ
    import settings
    from django.core.management import execute_manager
    
    
    setup_environ(settings)
    execute_manager(settings, argv=['runserver', '0.0.0.0:2123'])

# Turn off output buffering so the parent objc process can see our output property
class Unbuffered:
    def __init__(self, stream):
        self.stream = stream
    def write(self, data):
        self.stream.write(data)
        self.stream.flush()
    def __getattr__(self, attr):
        return getattr(self.stream, attr)

import sys
sys.stdout = Unbuffered(sys.stdout)

def migrate():
    import importlib
    from django.core.management import call_command
    call_command('syncdb', interactive=False)

    # if no superuser exists, create it
    from django.contrib.auth.models import User
    try:
        User.objects.get(pk=1)
    except User.DoesNotExist:
        User.objects.create_superuser('admin', 'example@example.com', 'admin')

    from django.conf import settings
    from CMi.base.models import Version

    for app in settings.INSTALLED_APPS:
        try:
            upgrade = importlib.import_module(app+'.upgrade')

            versions = [int(item_name[len('upgrade_'):]) for item_name in sorted(dir(upgrade)) if item_name.startswith('upgrade_')]

            app_version = Version.objects.get_or_create(app=app, defaults={'version': max(versions)})[0]
            for version in versions:
                if version > app_version.version:
                    print 'upgrading %s: %s -> %s' % (app, app_version.version, version)
                    app_version.version = version
                    getattr(upgrade, 'upgrade_%s' % version)()
                    app_version.save()
        except ImportError:
            pass

def run_sql(statements):
    from django.db import connection
    cursor = connection.cursor()
    for statement in statements.split(';'):
        cursor.execute(statement)
