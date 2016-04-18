#!/usr/bin/env python
import os
import sys
sys.path.insert(0, os.path.split(os.getcwd())[0]) # for embedded use
sys.path.insert(1, os.path.join(os.path.split(os.getcwd())[0], 'django')) # for development
sys.path.insert(2, os.path.abspath(os.path.join(os.path.split(__file__)[0], '../../django')))
sys.path.insert(3, os.path.abspath(os.path.join(os.path.split(__file__)[0], '..')))

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "CMi.settings")

    from CMi import migrate
    migrate()

    from django.core.management import execute_from_command_line

    execute_from_command_line(sys.argv)
