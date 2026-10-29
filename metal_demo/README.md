# CMi Metal demo

A small standalone AppKit + MetalKit app that recreates the CMi web frontend's
Metro-style tile UI: tiles flip in and out in 3D with staggered per-tile delays,
and a focus highlight moves with the arrow keys.

```sh
cd metal_demo
swift run
```

Keys: arrows move focus, Return/Enter opens the focused tile, Escape/Backspace goes
back. Clicking a tile focuses and opens it; clicking the back arrow goes back.

`CMI_SNAPSHOT_DIR=scratch/shots swift run` plays a short scripted navigation,
writes offscreen renders as PNGs into that folder and quits (that's how
`screenshot_*.png` were made).

## Files

- `Animation.swift` – timings, delays, CSS `ease` bezier, transition state
- `Level.swift` – layout of a menu level (header + tile table), focus, flip in/out, per-instance data
- `Atlas.swift` – draws tile labels/icons with AppKit/Core Text into one texture atlas per level
- `Renderer.swift` – Metal pipeline; shader source compiled at runtime with `makeLibrary(source:)`
- `MediaCenter.swift` – navigation (go/back/history), back button, clock, draw order
- `Content.swift` – fake menu data; `main.swift` – window and input; `Snapshots.swift` – offscreen PNG self-test

## How the CSS maps to the Metal version

Each level is one instanced draw call: one quad per tile, with per-instance rect,
atlas UVs, gradient colors, opacity, rotateY angle, pivot and perspective.

| CMi web frontend | Here |
| --- | --- |
| `.tiles td { transform: rotateY(150deg) }`, `.tile { opacity: 0 }` | resting state of a new tile |
| `flip_in()`: `rotateY(0deg)`, opacity 1, `transitionDuration` 300ms | `Level.flipIn` |
| `.started .flip_N { transition-delay: max(40, N*(40 - N//2))ms }` (views.py `css()`) | `CMi.flipInDelay` |
| `flip_out()`: `rotateY(-90deg)`, delay `min(i,10)*50`ms, opacity unchanged | `Level.flipOut`, `CMi.flipOutDelay` |
| default timing function `ease` = `cubic-bezier(.25,.1,.25,1)` | `CubicBezier.ease` |
| `transform-origin-x: -(offset().left)` (pivot at the page's left edge) | pivot x = 0 in the vertex shader |
| `.tiles { perspective: 1900px }` (retina CSS), perspective-origin 50% 50% of the table | `w = (d - z) / d` around the table center, output as clip-space w (perspective-correct UVs) |
| transitions start from the current value | `TileTransition.retarget` samples the current angle/opacity |
| `.header` opacity set to 1/0 with no transition | header pops in on flip in, vanishes on flip out |
| old `.tiles` container gets z-index 100, new one 0 | outgoing levels are drawn on top of the incoming one |
| `#back_link` jQuery `animate({opacity}, 300)` (swing) | `swing()` |
| `.tile`, `.tile.focus`, `.tile.pressed`, body gradients | `Palette` (horizontal gradients in the fragment shader) |
| sizes from `style2-retina.css` (200px big tiles, 15px text, 5px spacing, top 60 / left 100) | `Layout` (CSS px = points) |

Rotation follows CSS `rotateY`: `x' = cos(a)x + sin(a)z`, `z' = -sin(a)x + cos(a)z`
with z toward the viewer. So a tile at 150° starts behind and to the left of the
screen edge, mirrored, and swings into place. At -90° it swings toward the viewer
and off to the left. Backfaces are visible, like the CSS default.

### Differences

- Font: Century Gothic isn't installed with macOS, so it falls back to Avenir Next
  (the browser would have fallen back to Verdana). Line height is approximated as 1.2em.
- Icons are SF Symbols instead of the SVGs in `web_frontend/CMi/media`.
- The ajax round trip between `flip_out()` and `flip_in()` is simulated with a fixed 30ms.
- Back uses the same flip out / flip in as forward, exactly like `back()` in cmi.js.
  The animation isn't mirrored.
- Lists don't scroll (no `intoViewport`), and the list's `extra_info` text follows the
  title (like the screenshots) instead of floating right.
- Tiles are removed when their animation ends, not after `300ms * tileCount`. The
  difference isn't visible.
