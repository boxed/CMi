#!/usr/bin/env python

# Run these tests with py.test

from CMi.engine import *

def test_classification():
    # Not supported:
    # Boston Legal - 420 - Patriot Acts.avi|tv show|boston legal

    s = """
    Star Trek The Next Generation/Season 7/Star Trek The Next Generation Season 7 Episode 21 - Firstborn.avi|tv show|star trek the next generation|(7, 21)
    Glee S3.E18 (xCrazy0328x)/Glee S3.E18.avi|tv show|glee|(3, 18)
    House.S07E23.Moving.On.HDTV.XviD-2HD.avi|tv show|house|(7, 23)
    [PDTV-Xvid-Mp3-ITA] Dexter S05E11 [CR-Bt].avi|tv show|dexter|(5, 11)
    Glee.S02E22.HDTV.XviD-LOL.[VTV].avi|tv show|glee|(2, 22)
    The.Colbert.Report.2011.05.31.James.B.Stewart.HDTV.XviD-FQM.[VTV].avi|tv show|the colbert report|2011-05-31 00:00:00
    The.Daily.Show.2011.05.31.Jimmy.Fallon.HDTV.XviD-FQM.[VTV].avi|tv show|the daily show|2011-05-31 00:00:00
    (download at superseeds.org) Penn And Teller Fool Us S01E05 WS PDTV XviD-SuperS|tv show|penn and teller fool us|(1, 5)
    (download at superseeds.org) Penn.And.Teller.Fool.Us.S01E07.WS.PDTV.XviD-SuperS|tv show|penn and teller fool us|(1, 7)
    [ www.Speed.Cd ] - Penn.And.Teller.Fool.Us.S01E08.720p.HDTV.x264-ANGELiC|tv show|penn and teller fool us|(1, 8)
    [ www.TorrentDay.com ] - Penn.And.Teller.Fool.Us.S01E04.HDTV.XviD-COHD|tv show|penn and teller fool us|(1, 4)
    [ www.TorrentDay.com ] - Penn.And.Teller.Fool.Us.S01E06.HDTV.XviD-BARGE|tv show|penn and teller fool us|(1, 6)
    [ www.TorrentDay.com ] - So.You.Think.You.Can.Dance.S08E18.Top.8.Perform.HDTV.XviD-FQM|tv show|so you think you can dance|(8, 18)
    [ www.TorrentDay.com ] - So.You.Think.You.Can.Dance.S08E19.2.of.8.Voted.Off.HDTV.XviD-FQM|tv show|so you think you can dance|(8, 19)
    Brotherhood.of.the.Rose.1989.Eng.DVDRip.XVID|movie|brotherhood of the rose|1989
    Crazy.Stupid.Love.DVDRip.XviD-TWiZTED|movie|crazy stupid love|0
    Friends with Benefits 2011 R5 LiNE READNFO XViD - IMAGiNE|movie|friends with benefits|2011
    In Time 2011 TS XviD READNFO - MiSTERE|movie|in time|2011
    So.You.Think.You.Can.Dance.S08E20.Top.6.Perform.HDTV.XviD-FQM.avi|tv show|so you think you can dance|(8, 20)
    X-Men First Class 2011 R5 LiNE READNFO XViD - IMAGiNE|movie|x men first class|2011
    Your Highness (2011) DVDRip XviD-MAXSPEED|movie|your highness|2011
    White Collar S02E14 Payback HDTV XviD-FQM|tv show|white collar|(2, 14)
    White.Collar.S02E10.Burkes.Seven.HDTV.XviD-FQM.avi|tv show|white collar|(2, 10)
    Boston Legal - [S05E01] - Smoke Signals.avi|tv show|boston legal|(5, 1)
    Boston Legal - 05x02 - Guardians and Gatekeepers.avi|tv show|boston legal|(5, 2)
    Boston Legal - 5x2 - Dances With Wolves.avi|tv show|boston legal|(5, 2)
    Boston Legal - (S05E04) - True Love.avi|tv show|boston legal|(5, 4)
    Glee S03E06 Mash Off HDTV XviD-LOL [eztv]|tv show|glee|(3, 6)
    Glee S03E06 Mash Off HDTV XviD-LOL [eztv].avi|tv show|glee|(3, 6)
    Greys Anatomy S08E08 Heart-Shaped Box HDTV.XviD-LOL.[VTV].avi|tv show|greys anatomy|(8, 8)
    House S08E05 The Confession HDTV XviD-ASAP [eztv]|tv show|house|(8, 5)
    House S08E06 Parents HDTV XviD-2HD [eztv]|tv show|house|(8, 6)
    House.S08E03.HDTV.XviD-LOL.avi|tv show|house|(8, 3)
    House.S08E04.HDTV.XviD-LOL.avi|tv show|house|(8, 4)
    30.Minutes.Or.Less.2011.BDRip-HDT.avi|movie|30 minutes or less|2011
    Iron Man 2008.720p BluRay DTS x264-ESiR|movie|iron man|2008
    Iron.Man.2.2010.720p.BluRay.x264-WiKi|movie|iron man 2|2010
    Midnight.in.Paris.DVDRip.XviD-TARGET|movie|midnight in paris|0
    Water for Elephants (2011) DVDRip XviD-MAXSPEED|movie|water for elephants|2011
    Where.The.Wild.Things.Are.720p.Bluray.x264-HUBRIS|movie|where the wild things are|0
    1000.Ways.To.Die.S05E22.HDTV.XviD-aAF|tv show|1000 ways to die|(5, 22)
    90210.S04E10.480p.WEB-DL.x264-mSD|tv show|90210|(4, 10)
    The X Files-I Want To Believe[2008]DvDrip-aXXo|movie|the x files i want to believe|2008
    X-Files 1x24 - The Erlenmeyer Flask.avi|tv show|x files|(1, 24)
    The.Colbert.Report.2011.06.07.Sugar.Ray.Leonard.HDTV.XviD-FQM.[VTV].avi|tv show|the colbert report|2011-06-07 00:00:00
    (download at superseeds.org) Penn.And.Teller.Fool.Us.S01E07.WS.PDTV.XviD-SuperS|tv show|penn and teller fool us|(1, 7)
    [ www.Speed.Cd ] - Penn.And.Teller.Fool.Us.S01E08.720p.HDTV.x264-ANGELiC|tv show|penn and teller fool us|(1, 8)
    [ www.Torrenting.com ] - Triumph of the Nerds (1996)-DVDRIp Xvid-THC|movie|triumph of the nerds|1996
    A.Separation.2011.LiMiTED.BDRip.XviD- LPD|movie|a separation|2011
    Arthur Christmas 2011 TS AVI -THEONE1982-|movie|arthur christmas|2011
    Cowboys.And.Aliens.2011.SWESUB.DVDRip.x264.AC3-snuttebullen|movie|cowboys and aliens|2011
    The.Women.On.The.6th.Floor.2010.SWESUB.DVDRip.XviD-CrilleKex|movie|the women on the 6th floor|2010
    X-Men The Last Stand|movie|x men the last stand|0
    How I Met Your Mother S07E06 - 2011 - 720p - 200MB-sD|tv show|how i met your mother|(7, 6)
    Doctor.Who.2005.6x09.Night.Terrors.720p.HDTV.x264-FoV.mkv|tv show|doctor who 2005|(6, 9)
    Futurama/Season 1/S1E02.avi|tv show|futurama|(1, 2)
    Futurama/Season 1/S1EP03.avi|tv show|futurama|(1, 3)
    Futurama/Season 2/S2E02.avi|tv show|futurama|(2, 2)
    Men in Black 2 - [2002] HDDVDRip 720p H264-3Li|movie|men in black 2|2002
    Men.In.Black.1997.720p.BRRip.XviD.AC3-anoXmous|movie|men in black|1997
    Glee S03E21 HDTV XviD-AFG/Glee S03E21 HDTV XviD-AFG/Glee S03E21 HDTV XviD-AFG/Glee S03E21 HDTV XviD-AFG.avi|tv show|glee|(3, 21)
    Glee.S03E22.HDTV.x264-LOL.[VTV].mp4|tv show|glee|(3, 22)
    Smash.S01/Smash.S01E05.HDTV.x264-LOL.Let's.Be.Bad.mp4|tv show|smash|(1, 5)
    Smash.S01/Smash.S01E06.HDTV.x264-LOL.Chemistry.mp4|tv show|smash|(1, 6)
    Smash.S01/Smash.S01E07.HDTV.x264-LOL.The.Workshop.mp4|tv show|smash|(1, 7)
    Smash.S01/Smash.S01E08.HDTV.x264-LOL.The.Coup.mp4|tv show|smash|(1, 8)
    Smash.S01/Smash.S01E09.HDTV.XviD-FQM.Hell.on.Earth.avi|tv show|smash|(1, 9)
    Smash.S01/Smash.S01E10.HDTV.x264-LOL.Understudy.mp4|tv show|smash|(1, 10)
    Smash.S01/Smash.S01E11.HDTV.x264-LOL.The.Movie.Star.mp4|tv show|smash|(1, 11)
    Smash.S01/Smash.S01E12.HDTV.x264-LOL.Publicity.mp4|tv show|smash|(1, 12)
    Smash.S01/Smash.S01E13.HDTV.x264-LOL.Tech.mp4|tv show|smash|(1, 13)
    Smash.S01/Smash.S01E14.HDTV.x264-LOL.Previews.mp4|tv show|smash|(1, 14)
    Smash.S01/Smash.S01E15.HDTV.x264-LOL.Bombshell.mp4|tv show|smash|(1, 15)
    Smash.S01/Smash.S01E04.HDTV.x264-LOL.The.Cost.of.Art.mp4|tv show|smash|(1, 4)
    Enlightened Season 1 Complete 720p/Enlightened.S01E01.720p.HDTV.x264.mkv|tv show|enlightened|(1, 1)
    Awake - The Complete Season 1 [HDTV]/Awake.S01E01.HDTV.x264-LOL.mp4|tv show|awake|(1, 1)
    Awake - The Complete Season 1 [HDTV]/Awake.S01E02.HDTV.x264-LOL.mp4|tv show|awake|(1, 2)
    Merlin..Season.1/Merlin S01E05 Lancelot.avi|tv show|merlin|(1, 5)
    Unforgettable.S01/Unforgettable.S01E01.HDTV.XviD-LOL.Pilot.avi|tv show|unforgettable|(1, 1)
    Merlin.Season.1/Merlin S01E05 Lancelot.avi|tv show|merlin|(1, 5)
    The.Big.Bang.Theory.S06E19.HDTV.Subtitulado.Esp.SC.avi|tv show|the big bang theory|(6, 19)
    Nurse Jackie/Nurse Jackie Season1/Nurse_Jackie-S01E01-XviD.avi|tv show|nurse jackie|(1, 1)
    """

    def classify(s):
        raw_data, classification, name, result = s.split('|')
        r = match_file(raw_data)
        r = (r[0], r[1], r[2], str(r[3]))
        if r:
            if r[0] != classification or r[2] != name or r[3] != result:
                assert False, 'FAILED: %s\n\tFound:   \t%s\n\tExpected:\t%s' % (s, r, (classification, raw_data, name, result))

    for line in s.strip().split('\n'):
        classify(line.strip())
