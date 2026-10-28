def title_sort_key(s):
    """
    @type s: str
    """
    foo = s.lower()
    if foo.startswith('the '):
        return foo[len('the '):]
    return foo

class ListItem(object):
    def __init__(self, url=None, title=None, extra=None, command=None):
        self.url = url
        self.title = title
        self._extra = extra
        self.command = command

    def extra(self):
        return self._extra or ''

    def __str__(self):
        return str(self.title or '')

    def __repr__(self):
        return str(self.title or '')

def chunks(l, n, pad=False):
    """ Yield successive n-sized chunks from l.
    """
    for i in range(0, len(l), n):
        foo = l[i:i+n]
        if pad:
            foo += [None for x in range(n-len(foo))]
        yield foo
