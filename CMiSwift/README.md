# CMi in Swift

A native rewrite of CMi: the Metro-style tile UI drawn with Metal, playback with VLCKit, and the media
library and Plex support in Swift. It reads and writes the same database and `plex.json` as the old
Python/Django version (`~/Library/Application Support/CMi/`), so you can switch back and forth.

```sh
./build_app.sh            # release build into build/CMi.app
./build_app.sh debug      # faster to build
./build_app.sh release --universal   # arm64 + x86_64
open build/CMi.app
swift test                # library and Plex tests
```

VLCKit comes from `../Frameworks/VLCKit.framework`. Its install name only resolves from inside an app
bundle, which is why the app is run from `build/CMi.app` rather than with `swift run`.

## Layout

- `Sources/CMiCore` – the media library: filename classification, the SQLite database (Django's schema),
  sorting downloads into `TV Shows` and `Movies`, trashing watched episodes, TVmaze and IMDb lookups.
- `Sources/CMiPlex` – Plex: sign in with a plex.tv/link code, server discovery, browsing, progress.
- `Sources/CMiSVT` – SVT Play: the start page's lists, programs A–Ö and their seasons, streams from
  api.svt.se. It reads the data svtplay.se embeds in its pages (like svtplay-dl does), so a redesign of the
  site can break it. What you've watched is kept in `svtplay.json`, since SVT Play has no login.
- `Sources/CMi` – the app.
  - `UI/` – the Metal tile renderer and the menu navigation (ported from the web frontend's CSS and cmi.js), with
    Metro's turnstile page transitions and press feedback (`Motion.swift`).
  - `Menus/` – what's on each screen.
  - `Playback/` – the VLCKit player and the on-screen controls.
  - `App/` – window, input, media keys, the periodic library scan.

## Keys

In menus: arrows move, Return opens, Escape or Backspace goes back, typing jumps to the first title starting with what you typed, ⌘R refreshes. `/` or ⌘F searches
local TV shows and movies, Plex and SVT Play from anywhere; type to search, Backspace deletes.

While playing: Space plays/pauses, Left/Right skip 30 seconds, Up/Down change the volume, Return, Escape
or M show the on-screen controls (then Left/Right pick one and Space/Return presses it), Backspace stops.
Media keys work too. Clicking the progress bar jumps to that point.

## Settings

Change with `defaults write net.kodare.CMi <key> <value>`, then restart CMi:

- `zoom` (`-float`, default 1.5) – how much bigger the menus are drawn than the old web frontend.
- `networkCaching` / `fileCaching` (`-int`, milliseconds, default 8000 / 3000) – how much VLC buffers.
- `readAheadMegabytes` (`-int`, default 256) – how far ahead VLC may download when the network is faster than
  the video, so a good connection builds up minutes of buffer for Plex, SVT Play and network shares.

## Environment variables

- `CMI_SUPPORT_FOLDER` – use another folder for the database and `plex.json`.
- `CMI_WINDOWED=1` – a normal window instead of taking over the screen.
- `CMI_PLEX_SYNC_SECONDS` – how often Plex pages with a next episode reload (default 3600), so watching on
  another device shows up here.
- `CMI_SNAPSHOT_DIR=dir` (with optional `CMI_SNAPSHOT_PATH=enter,down,enter,escape`) – press keys,
  save offscreen renders as PNGs, and quit. Handy where screen capture isn't allowed.

## Not carried over from the old app

- The Python plugin API, the weather and calendar tiles and the file browser (all disabled or empty).
- The Apple IR remote (replaced by media keys).
