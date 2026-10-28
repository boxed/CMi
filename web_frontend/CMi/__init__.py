import sys

# Turn off output buffering so the parent objc process can see our output properly
sys.stdout.reconfigure(line_buffering=True)

def migrate():
    from django.core.management import call_command
    # fake_initial lets databases created by the old syncdb based setup adopt the migrations
    call_command('migrate', fake_initial=True, interactive=False)

    # if no superuser exists, create it
    from django.contrib.auth.models import User
    if not User.objects.filter(is_superuser=True).exists():
        User.objects.create_superuser('admin', 'example@example.com', 'admin')
