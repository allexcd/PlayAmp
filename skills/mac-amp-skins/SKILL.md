---
name: mac-amp-skins
description: Design and build skins for the Mac-Amp music player (any look, from recolors to fully custom players like turntables, VU-meter radios, boomboxes or Walkmans). Use when asked to create, change, fix or preview a Mac-Amp skin, or to turn a design idea or reference image into one.
---

# Designing Mac-Amp skins

Mac-Amp is a retro macOS music player with snap-together windows: **player**, **equalizer**, **playlist** and **skins**. A skin can change everything about how they look. The player window can be redesigned completely with a JSON **layout**: any size and shape, images, fonts, and parts that move with the music.

The cassette deck and the turntable are just two examples. Anything you can draw with rectangles, ellipses, images, text, buttons and sliders works.

## Pick the right level

| Goal | Use | Effort |
|---|---|---|
| New colors on an existing design | `colors` (+ `basedOn`) | a few lines |
| Textures, printed artwork, other fonts, rounded corners | `images`, `fonts`, `shape` | + image files |
| A different player altogether (new object, new arrangement) | `layout` | a full design |

Always start from the lowest level that achieves the brief. Everything you leave out is inherited from `basedOn` (then from Classic), so skins stay short.

## Workflow

1. **Understand the brief.** Name the real-world object or mood, its materials and palette, which moving parts make it feel alive, and the window size. Players are usually 250–320 pt wide and 110–200 pt tall.
2. **Create the skin** in the user's Skins folder:
   `~/Library/Containers/dev.macamp.prototype/Data/Library/Application Support/MacAmp/Skins/`
   - Colors-only skins can be a single `<Name>.json`.
   - Skins with images or font files must be a folder `<Name>/` containing `skin.json` and the files.
   - In the app, **Skins panel → FOLDER** opens and creates this folder, with examples in it.
3. **Write `skin.json`.** Use [reference.md](reference.md) for every allowed key, token, element type, binding, placeholder and action, and copy patterns from [examples/](examples).
4. **Make images** (if any) with code, e.g. Python with Pillow, an SVG rendered to PNG, or a Swift/AppKit script:
   - Draw at 2–3× the point size the frame will use, so they stay sharp on Retina screens.
   - Use transparent PNGs for round or irregular shapes.
   - Textures with `"mode": "tile"` must tile seamlessly.
5. **Validate**, and fix every error. Keep warnings to a minimum.
   ```bash
   MacAmp --validate-skin "<skin.json or skin folder>"
   ```
6. **Render a preview and look at it.** Fix anything that looks off, then repeat steps 5–6.
   ```bash
   MacAmp --render-skin "<skin.json or skin folder>" --window all --state playing --progress 0.4
   ```
   - The image is written next to the skin (`preview.png`, or `<name>-preview.png`), or to `--out <file.png>`.
   - Check `--state paused` and `--state stopped` too. Bound values like tonearms and LEDs use `idle` and `visible` there.
7. **Tell the user** to open the Skins panel (**SK** or ⌘K), press **RELOAD**, and click the new skin.

`MacAmp` means the app's executable:
- installed app: `/Applications/MacAmp.app/Contents/MacOS/MacAmp`
- source checkout: `swift run MacAmp …` or `.build/debug/MacAmp …`

The installed app is sandboxed, so its command-line tools can only read and write inside the Skins folder above. Keep skins and outputs there, or use a source build.

## Layout essentials

```json
"layout": {
  "size": [300, 156],
  "elements": [
    { "type": "rect", "frame": [0, 0, 300, 156], "corner": 10, "fill": { "linear": ["panelTop", "panelBottom"], "angle": 90 } },
    { "type": "dragArea", "frame": [0, 0, 280, 18] },
    { "type": "button", "frame": [281, 4, 13, 12], "action": "hide", "label": "×" },
    { "type": "text", "frame": [12, 24, 120, 22], "text": "{time}", "font": "display", "fontSize": 18 },
    { "type": "button", "frame": [12, 129, 24, 16], "action": "playPause", "label": "▶" }
  ]
}
```

- **Coordinates:** `frame` is `[x, y, width, height]` in points from the parent's top-left. Group children are relative to the group.
- **Drawing order:** elements draw in order, so later ones sit on top. Draw backgrounds first and glass highlights last.
- **Paint** is a color token (`"display"`), `"#RRGGBB"` or `"#RRGGBBAA"`, `{ "linear": [...], "angle": 90 }` (0° = left→right, 90° = top→bottom), or `{ "radial": [...] }`. Prefer tokens for colors the user may want to retheme.
- **Numbers can follow playback:** `{ "bind": "progress", "from": 18, "to": 34, "idle": 0 }`. Every binding runs 0…1; `idle` applies while stopped.
- **Images:** `"@deck"`, `"@player"` and similar refer to the skin's `images` slots. Built-in layouts use these, so child skins can add textures without copying the layout.
- **Fonts:** `font` is a role (`display`, `ui`, `label`), an installed font name, or a `.ttf`/`.otf` file in the skin folder.

### Must-haves (the validator checks these)

- A `dragArea`, or the window can't be moved.
- A `playPause` (or `play`) button and a `hide` button (the close ×).
- Frames inside the layout size, and files inside the skin folder.
- Files are named relative to the skin folder. Absolute paths, `..` and symlinks that lead outside it are refused.
- Stay within the limits listed in [reference.md](reference.md) (layout size, element count, nesting, image size). Anything beyond them is ignored.

### Good practice

- Include the controls users expect: previous, next, stop, add (`⏏`), equalizer / playlist / skins toggles, position and volume sliders. Hidden hotspots (`"style": "none"`) over artwork are fine.
- Keep text readable: at least 6 pt, and strong contrast against its background.
- Keep the width near 275 pt so the 275 pt equalizer and playlist line up when docked. Wider players work, but look less tidy.
- Use `"scroll": true` for titles, since song names are long.
- Name the skin after the design, not "Test".

## Recipes

| Effect | How |
|---|---|
| Spinning record, reel, knob | `group` with `"spin": 33.33` (rpm, only while playing) |
| Tonearm or pointer that follows the song | `group` with `"pivot": [x, y]` and `"rotation": { "bind": "progress", "from": a, "to": b, "idle": rest }` |
| VU needle | `group` with `"clip": true` around the meter, and a needle group rotated by `{ "bind": "level", "from": -42, "to": 40, "idle": -42 }` |
| Tape packs that wind across | two `ellipse`s with `"radius": { "bind": "progress", "from": 22, "to": 8.5 }` (and the reverse) |
| Lamp or LED | two ellipses with `"visible": "playing"` and `"visible": "!playing"` |
| Tuning dial or needle you can drag to seek | `slider` with `"bind": "position"`, transparent `track`/`fill`, and a thin `knob` (`"knobSize": [2, 28]`) |
| Vertical fader | `slider` with `"vertical": true` |
| Artwork as buttons | `button` with `"image"` / `"pressedImage"`, or `"style": "none"` over drawn art |
| Glass or sheen | a last `rect`/`ellipse` with a white→transparent gradient |
| Reuse the animated cassette | element `{ "type": "cassette", "frame": [...] }` |

## Examples

- [examples/vu-radio/skin.json](examples/vu-radio/skin.json): a full custom layout with two VU meters, a tuning dial that seeks, a spinning knob, a vertical volume fader and an LED. No images.
- [examples/walnut/](examples/walnut): based on the built-in Turntable, adding wood textures, printed record-label art and different fonts.
- [examples/midnight-tape.json](examples/midnight-tape.json): colors and shape only, on the cassette face.
- The built-in Turntable layout is in the app source at `Sources/MacAmpCore/BuiltInLayouts.swift`. It's a complete record player in the same JSON format.

## Before you finish

- `--validate-skin` reports 0 errors.
- You looked at previews for playing and stopped.
- Text is legible, controls are reachable, and nothing important is clipped.
- Image files are in the skin folder and referenced by relative names.
