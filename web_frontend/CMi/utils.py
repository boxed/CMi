def title_sort_key(s):
    """
    @type s: str or unicode
    """
    foo = s.lower()
    if foo.startswith('the '):
        return foo[len('the '):]
    return foo