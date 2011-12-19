"""
This file demonstrates two different styles of tests (one doctest and one
unittest). These will both pass when you run "manage.py test".

Replace these with more appropriate tests for your application.
"""

from django.test import TestCase

class SimpleTest(TestCase):
    """
    Test TODO:

    add 2 suggested shows
    assert that / has "2 new show"
    assert that /tvshows/suggested/ has the new shows
    follow the "add" link for show 1
    assert that /tvshows/suggested/ now has only 1 new show
    follow the "add" link for show 2
    assert that we get back to /

    add two episodes to show 1
    asser that both episodes have position 0 and watched = False
    assert that /tvshows/1/ has two episodes
    assert that /tvshows/1/1/position/10/ sets position to 10
    assert that /tvshows/1/1/ended/ sets watched
    assert that /tvshows/1/ has one episode
    assert that /tvshows/1/2/ended/ sets watched
    assert that /tvshows/1/ returns ':back'

    """

    def test_basic_addition(self):
        """
        Tests that 1 + 1 always equals 2.
        """
        self.failUnlessEqual(1 + 1, 2)

__test__ = {"doctest": """
Another way to test that 1 + 1 is equal to 2.

>>> 1 + 1 == 2
True
"""}

