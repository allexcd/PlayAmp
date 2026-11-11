# Trimmed copy of SFBAudioEngine

This folder is a reduced copy of [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) 0.14.0 by Stephen F. Booth, used under the MIT license (see `LICENSE.txt`). Source files are unmodified apart from the two noted below.

## Why

The full engine links codec libraries under the LGPL (LAME, mpg123, libsndfile, Musepack, TrueAudio). The app only plays nine formats and needs none of them, and the LGPL's relinking terms are hard to meet for an App Store build. This copy keeps only what the player uses, so the app is built from MIT and BSD code plus Apple's own decoders.

## What is kept

- The player, input sources and output targets.
- Decoders: Core Audio (MP3, WAV, AIFF, AAC, M4A and more, decoded by macOS), FLAC, Ogg Vorbis and Ogg Opus.
- The author's small MIT utility packages, and the BSD-licensed Xiph libraries (ogg, FLAC, opus, vorbis).

## What was removed

- Decoders for MPEG via mpg123, libsndfile, Musepack, TrueAudio, Monkey's Audio, WavPack, Ogg Speex, Shorten, tracker modules and DSD.
- All encoders, the converter and exporter, the ReplayGain analyzer, and tag reading and writing (TagLib).

## Files changed

- `Package.swift`: lists only the remaining dependencies and source folders.
- `Sources/CSFBAudioEngine/include/SFBAudioEngine/SFBAudioEngine.h`: imports only the remaining headers.

## Updating

Copy the same files from a newer release, reapply the two edits, then run the tests: `CodecTests` and `PlaybackTests` decode, seek and play every supported format.
