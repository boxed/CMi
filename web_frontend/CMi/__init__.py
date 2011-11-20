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
    execute_manager(settings, argv=['runserver', '127.0.0.1:2123'])

# Turn off outpub buffering so the parent objc process can see our output property
class Unbuffered:
    def __init__(self, stream):
        self.stream = stream
    def write(self, data):
        self.stream.write(data)
        self.stream.flush()
    def __getattr__(self, attr):
        return getattr(self.stream, attr)

import sys
sys.stdout=Unbuffered(sys.stdout)