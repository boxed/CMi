# CMi

CMi is pronounced "See me!", because it wants you to. It's a Mac-based media center like for example XBMC, Boxee, etc. 

![CMi version 2.0](https://github.com/boxed/CMi/raw/master/screenshots/2013-04-21_1.png)


## Why I wasn't satisfied with existing systems

Short version: death by a thousand paper cuts.

Longer version: XBMC was the closest to an acceptable system but I still had to write tons of python to sit in front of it just so it would understand the files I was downloading. Then it had all these annoying issues like when you press play there is no visual indication that you actually pressed a button until the video starts playing, so you hit play again and then that pauses the video when it does eventually show up. Oh and the GUI where up on the remote moves you some random direction because the skin doesn't handle these things. Blech.

## What does it do?

* It scans your download folder and automatically figures out if you have episodes from TV shows or movies in there and will handle that correctly. Without any configuration. At all.
* It keeps track of what you've watched.
* Even if you get a power outage it will still remember where you were in the video when you restart the video.
* It will automatically clear out old files by sending them to the trash (not deleting them without a trace!)
* It plays from Plex and SVT Play too.
* It has some nice animations that were heavily inspired by Microsofts Metro style.

## Building

CMi is written in Swift: the Metro-style tile UI drawn with Metal, playback with VLCKit. The database,
`plex.json` and `svtplay.json` are kept in `~/Library/Application Support/CMi/`.

```sh
cd CMiSwift
./build_app.sh            # release build into build/CMi.app
./build_app.sh debug      # faster to build
./build_app.sh release --universal   # arm64 + x86_64
open build/CMi.app
swift test                # library and Plex tests
```

VLCKit comes from `Frameworks/VLCKit.framework`. Its install name only resolves from inside an app
bundle, which is why the app is run from `build/CMi.app` rather than with `swift run`.

## Layout

- `CMiSwift/Sources/CMiCore` – the media library: filename classification, the SQLite database,
  sorting downloads into `TV Shows` and `Movies`, trashing watched episodes, TVmaze and IMDb lookups.
- `CMiSwift/Sources/CMiPlex` – Plex: sign in with a plex.tv/link code, server discovery, browsing, progress,
  downloads.
- `CMiSwift/Sources/CMiSVT` – SVT Play: the start page's lists, programs A–Ö and their seasons, streams from
  api.svt.se. It reads the data svtplay.se embeds in its pages (like svtplay-dl does), so a redesign of the
  site can break it. What you've watched is kept in `svtplay.json`, since SVT Play has no login.
- `CMiSwift/Sources/CMi` – the app.
  - `UI/` – the Metal tile renderer and the menu navigation, with Metro's turnstile page transitions and
    press feedback (`Motion.swift`).
  - `Menus/` – what's on each screen.
  - `Playback/` – the VLCKit player and the on-screen controls.
  - `App/` – window, input, media keys, the periodic library scan.

## Plex

Open the Plex tile and enter the code it shows at plex.tv/link. CMi finds your servers and connects to the
first address that answers. You can also skip the sign in by creating
`~/Library/Application Support/CMi/plex.json` yourself:

    {"url": "http://192.168.1.10:32400", "token": "YOUR_PLEX_TOKEN"}

## Keys

In menus: arrows move, Return opens, Escape or Backspace goes back, typing jumps to the first title starting with what you typed, ⌘R refreshes. `/` or ⌘F searches
local TV shows and movies, Plex and SVT Play from anywhere; type to search, Backspace deletes.

While playing: Space plays/pauses, Left/Right skip 30 seconds, Up/Down change the volume, S switches subtitles,
Return, Escape or M show the on-screen controls (then Left/Right pick one and Space/Return presses it), Backspace stops.
Media keys work too. Clicking the progress bar jumps to that point.

## Subtitles

S, or the last of the on-screen controls, goes through the subtitles and then off. What you pick is remembered
for the show (or movie) and used for its next episodes. Until you've picked something:

- Local files start without subtitles. VLC finds subtitle files next to the video whose name contains the
  video's. When a download is filed away, its subtitles go with it: `Video.en.srt` next to it, or in a `Subs`
  folder (`Subs/2_English.srt`, or `Subs/<video name>/…` for a season in one folder).
- Plex starts with what's chosen in Plex (per video, or by the account's subtitle settings). Subtitles in files
  of their own on the server are downloaded when playing starts.
- SVT Play starts with what SVT shows by default: translations of foreign speech and lines that are hard to hear.
  "Allt tal" has everything.

## Plex downloads

The two unwatched episodes after the Plex episode played last are downloaded to `Plex downloads` in the support
folder, so a bad connection can't stop them halfway, and they can be watched when the server can't be reached at
all: then the Plex screen lists them under "Continue watching". Downloaded episodes play from the file. What's
watched without a connection is told to the server once it's back. Watched episodes, and those of the show watched
before, are deleted. Interrupted downloads continue every 10 minutes.

## Settings

Change with `defaults write net.kodare.CMi <key> <value>`, then restart CMi:

- `zoom` (`-float`) – how much bigger the menus are drawn than their base size. Normally the home screen
  is zoomed to fill the height of the screen, and every other screen uses the same zoom.
- `networkCaching` / `fileCaching` (`-int`, milliseconds, default 8000 / 3000) – how much VLC buffers.
- `readAheadMegabytes` (`-int`, default 256) – how far ahead VLC may download when the network is faster than
  the video, so a good connection builds up minutes of buffer when playing from Plex.

## Environment variables

- `CMI_SUPPORT_FOLDER` – use another folder for the database and `plex.json`.
- `CMI_WINDOWED=1` – a normal window instead of taking over the screen.
- `CMI_PLEX_SYNC_SECONDS` – how often Plex pages with a next episode reload (default 3600), so watching on
  another device shows up here.
- `CMI_SNAPSHOT_DIR=dir` (with optional `CMI_SNAPSHOT_PATH=enter,down,enter,escape`) – press keys,
  save offscreen renders as PNGs, and quit. Handy where screen capture isn't allowed.
