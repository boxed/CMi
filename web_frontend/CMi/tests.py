#!/usr/bin/env python
import os
import sys
sys.path.append(os.getcwd())
sys.path.append(os.path.split(os.getcwd())[0]) # for embedded use
sys.path.append(os.path.join(os.path.split(os.getcwd())[0], 'django')) # for development

from CMi.engine import *

s = """
House.S07E23.Moving.On.HDTV.XviD-2HD.avi
[PDTV-Xvid-Mp3-ITA] Dexter S05E11 [CR-Bt].avi
Glee.S02E22.HDTV.XviD-LOL.[VTV].avi
The.Colbert.Report.2011.05.31.James.B.Stewart.HDTV.XviD-FQM.[VTV].avi
The.Daily.Show.2011.05.31.Jimmy.Fallon.HDTV.XviD-FQM.[VTV].avi
(download at superseeds.org) Penn And Teller Fool Us S01E05 WS PDTV XviD-SuperS
(download at superseeds.org) Penn.And.Teller.Fool.Us.S01E07.WS.PDTV.XviD-SuperS
[ www.Speed.Cd ] - Penn.And.Teller.Fool.Us.S01E08.720p.HDTV.x264-ANGELiC
[ www.TorrentDay.com ] - Penn.And.Teller.Fool.Us.S01E04.HDTV.XviD-COHD
[ www.TorrentDay.com ] - Penn.And.Teller.Fool.Us.S01E06.HDTV.XviD-BARGE
[ www.TorrentDay.com ] - So.You.Think.You.Can.Dance.S08E18.Top.8.Perform.HDTV.XviD-FQM
[ www.TorrentDay.com ] - So.You.Think.You.Can.Dance.S08E19.2.of.8.Voted.Off.HDTV.XviD-FQM
Bill.Bailey.Bewilderness.DVDRip.XViD
Bill.Bailey.Live.Cosmic.Jam.1996.DVDRip.XviD-VoMiT
Brotherhood.of.the.Rose.1989.Eng.DVDRip.XVID
Crazy.Stupid.Love.DVDRip.XviD-TWiZTED
Friends with Benefits 2011 R5 LiNE READNFO XViD - IMAGiNE
In Time 2011 TS XviD READNFO - MiSTERE
So.You.Think.You.Can.Dance.S08E20.Top.6.Perform.HDTV.XviD-FQM.avi
X-Men First Class 2011 R5 LiNE READNFO XViD - IMAGiNE
Your Highness (2011) DVDRip XviD-MAXSPEED
White Collar S02E14 Payback HDTV XviD-FQM
White.Collar.S02E10.Burkes.Seven.HDTV.XviD-FQM.avi
Boston Legal - 420 - Patriot Acts.avi
Boston Legal - [S05E01] - Smoke Signals.avi
Boston Legal - 05x02 - Guardians and Gatekeepers.avi
Boston Legal - 5x2 - Dances With Wolves.avi
Boston Legal - (S05E04) - True Love.avi
Glee S03E06 Mash Off HDTV XviD-LOL [eztv]
Glee S03E06 Mash Off HDTV XviD-LOL [eztv].avi
Greys Anatomy S08E08 Heart-Shaped Box HDTV.XviD-LOL.[VTV].avi
House S08E05 The Confession HDTV XviD-ASAP [eztv]
House S08E06 Parents HDTV XviD-2HD [eztv]
House.S08E03.HDTV.XviD-LOL.avi
House.S08E04.HDTV.XviD-LOL.avi
30.Minutes.Or.Less.2011.BDRip-HDT.avi
Iron Man 2008.720p BluRay DTS x264-ESiR
Iron.Man.2.2010.720p.BluRay.x264-WiKi
Midnight.in.Paris.DVDRip.XviD-TARGET
Water for Elephants (2011) DVDRip XviD-MAXSPEED
Where.The.Wild.Things.Are.720p.Bluray.x264-HUBRIS
X-Men The Last Stand
1000.Ways.To.Die.S05E22.HDTV.XviD-aAF
90210.S04E10.480p.WEB-DL.x264-mSD
The X Files-I Want To Believe[2008]DvDrip-aXXo
X-Files 1x24 - The Erlenmeyer Flask.avi
The.Colbert.Report.2011.06.07.Sugar.Ray.Leonard.HDTV.XviD-FQM.[VTV].avi
(download at superseeds.org) Penn.And.Teller.Fool.Us.S01E07.WS.PDTV.XviD-SuperS
[ www.Speed.Cd ] - Penn.And.Teller.Fool.Us.S01E08.720p.HDTV.x264-ANGELiC
[ www.Torrenting.com ] - Triumph of the Nerds (1996)-DVDRIp Xvid-THC
A.Separation.2011.LiMiTED.BDRip.XviD- LPD
Arthur Christmas 2011 TS AVI -THEONE1982-
Cowboys.And.Aliens.2011.SWESUB.DVDRip.x264.AC3-snuttebullen
The.Women.On.The.6th.Floor.2010.SWESUB.DVDRip.XviD-CrilleKex
X-Men The Last Stand
How I Met Your Mother S07E06 - 2011 - 720p - 200MB-sD
"""

def classify(s):
    r = match_file(s)
    if r:
        print '# %s\t\t\t"%s"' % (s, r[0]), r[1:]
    else:
        print '$', s

for line in s.strip().split('\n'):
    classify(line)