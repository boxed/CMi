def title_sort_key(s):
    """
    @type s: str or unicode
    """
    foo = s.lower()
    if foo.startswith('the '):
        return foo[len('the '):]
    return foo

class ListItem(object):
    def __init__(self, url, title, extra=None):
        self.url = url
        self.title = title
        self._extra = extra

    def extra(self):
        return self._extra or ''

    def __unicode__(self):
        return self.title or ''

    def __repr__(self):
        return self.title or ''

def chunks(l, n, pad=False):
    """ Yield successive n-sized chunks from l.
    """
    for i in xrange(0, len(l), n):
        foo = l[i:i+n]
        if pad:
            foo += [None for x in xrange(n-len(foo))]
        yield foo
