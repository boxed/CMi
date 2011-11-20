def ajax(request):
    return {'ajax': 'ajax' in request.REQUEST}