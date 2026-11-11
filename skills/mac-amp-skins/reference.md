# Mac-Amp skin reference

Generated from the app with `MacAmp --skin-reference`. Do not edit by hand; a test checks it matches the code.

```text
MAC-AMP SKIN REFERENCE

Skin keys: name, face (classic | cassette), basedOn, colors, images, fonts, shape, layout
Built-in skins: classic (Classic), cassette (Cassette Deck), turntable (Turntable)

COLOR TOKENS (colors: { token: "#RRGGBB" | "#RRGGBBAA" })
  display — LCD text, spectrum base, playlist titles
  displayBackground — LCD, playlist and slider backgrounds
  displayDim — secondary LCD text (track numbers, formats)
  displayHighlight — the playing track's title, peak markers
  playingRow — background of the playing playlist row
  panelTop — window gradient, top-left
  panelMid — window gradient, middle
  panelBottom — window gradient, bottom-right
  border — window outline and title-bar lines
  text — window titles and labels
  panelAccent — highlighted labels on the window body (EQ values, track count)
  buttonTop — button gradient, top
  buttonBottom — button gradient, bottom
  buttonPressed — pressed button
  buttonText — button labels
  sliderFillStart — slider fill, left
  sliderFillEnd — slider fill, right
  knob — slider and fader knobs
  spectrumHigh — spectrum bar tops
  spectrumMid — spectrum bar middles
  cassetteShell — cassette body (cassette face)
  cassetteLabel — cassette label (cassette face)
  cassetteStripe1 — label stripe (cassette face)
  cassetteStripe2 — label stripe (cassette face)
  cassetteInk — handwriting on the label (cassette and turntable faces)
  tape — tape ribbon and reel packs (cassette face)
  reel — reel hubs (cassette face), spindle (turntable face)
  deck — background of the cassette well / turntable plinth
  vinyl — the record (turntable face)
  recordLabel — the record's center label (turntable face)
  tonearm — tonearm and platter rim (turntable face)

IMAGE SLOTS (images: { slot: "file.png" | { "file": "file.png", "mode": "stretch" | "tile" } })
  panel — background of every window
  player — player window background (overrides panel)
  playlist — playlist window background (overrides panel)
  equalizer — equalizer window background (overrides panel)
  skins — skins window background (overrides panel)
  display — LCD areas, playlist and lists
  button — buttons
  buttonPressed — buttons while pressed
  deck — cassette well / turntable plinth
  cassetteLabel — artwork printed on the cassette label
  recordLabel — artwork on the record's center label (spins with it)

FONT ROLES (fonts: { role: "Installed Font Name" | "MyFont.ttf" })
  display — time, LCD text and the playlist
  ui — window titles, buttons and labels
  label — handwriting on the cassette / record label

SHAPE (shape: { ... }, all optional)
  windowCorner — corner radius of windows (points)
  buttonCorner — corner radius of buttons (points)
  cassetteWindow — "wide" | "twin" (cassette face)
  reels — "teeth" | "spokes" | "solid" (cassette face)
  label — "stripes" | "plain" (cassette face)

LAYOUT (layout: { "size": [width, height], "elements": [ ... ] }) — draws the whole player
  Frames are [x, y, width, height] in points from the parent's top-left. Later elements draw on top.
  Paint: token | "#RRGGBB(AA)" | { "linear": [stops], "angle": degrees } | { "radial": [stops] }
  Number or binding: 12 | { "bind": "<binding>", "from": a, "to": b, "idle": c }  (idle = value while stopped)
  File "@<slot>" uses the skin's image for that slot, if any.
  Common fields: frame, fill, stroke, strokeWidth, corner, opacity, visible ("binding" or "!binding"), help

LIMITS (skins are checked when loaded; anything outside these is ignored)
  skin.json up to 1000 KB; layout size 100–1600 × 40–1200 points
  up to 2000 elements, groups nested up to 8 deep; fontSize up to 400; text up to 500 characters
  images: bmp, gif, heic, jpeg, jpg, pdf, png, tif, tiff, webp; up to 25 MB and 8192 pixels a side
  files must be inside the skin's folder: no absolute paths, no "..", no symlinks that lead outside

ELEMENT TYPES
  rect — rectangle: fill, stroke, strokeWidth, corner
  ellipse — ellipse filling the frame, or a circle of `radius` centred in it: fill, stroke, strokeWidth, radius
  image — picture file: file, mode (stretch | tile | fit)
  text — text with {placeholders}: text, font, fontSize, weight, color, align, scroll
  spectrum — 20-band analyzer: fill (bars), gap, peaks, peakColor
  button — clickable: action, label, style (retro | plain | none), image, pressedImage, font, fontSize, color
  slider — drag control: bind (volume | balance | position), vertical, track, fill, knob, knobSize, knobImage
  group — container for children: rotation, spin (rpm while playing), pivot, clip
  dragArea — where the window can be dragged (every layout needs one)
  cassette — the built-in animated cassette, scaled to the frame

BUTTON ACTIONS
  playPause — play or pause
  play — play
  pause — pause
  stop — stop
  next — next track
  previous — previous track
  add — add files or folders
  shuffle — toggle shuffle
  repeat — cycle repeat off / all / one
  equalizer — show or hide the equalizer
  playlist — show or hide the playlist
  skins — show or hide the skins panel
  find — search the playlist
  toggleTime — switch elapsed / remaining time
  hide — hide the app (close button)
  minimize — minimize the player

BINDINGS (0…1)
  progress — position in the track
  playing — 1 while playing
  paused — 1 while paused
  stopped — 1 when nothing is loaded
  volume — volume
  balance — balance (0 left, 0.5 centre, 1 right)
  level — overall loudness, smoothed (good for VU needles)
  shuffle — 1 when shuffle is on
  repeat — 0 off, 0.5 all, 1 one
  remaining — 1 when the clock shows remaining time

TEXT PLACEHOLDERS ({name} in text and button labels)
  time — elapsed or remaining time, as the user chose (mm:ss)
  elapsed — elapsed time
  remaining — time left
  duration — track length
  title — full track title
  artist — artist (when the title is "Artist — Song")
  song — song name without the artist
  format — file type, e.g. MP3
  status — PLAY, PAUSE or STOP
  track — track number in the playlist
  count — number of tracks
  shuffle — SHUF or SHUF ●
  repeat — R:OFF, R:ALL or R:ONE
  volume — volume percent
  skin — skin name
```
