#!/usr/bin/env python
import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.split(__file__)[0], '../../')))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.split(__file__)[0], '..')))

args = ['CMi/manage.py', 'runserver', '0.0.0.0:19817', '--noreload']

if __name__ == "__main__":
    sys.stderr = sys.stdout
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "CMi.settings")
    
    from CMi import migrate
    migrate()

    from django.core.management import execute_from_command_line

    execute_from_command_line(args)
