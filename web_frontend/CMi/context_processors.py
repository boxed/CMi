def ajax(request):
    return {'ajax': 'ajax' in request.GET or 'ajax' in request.POST}