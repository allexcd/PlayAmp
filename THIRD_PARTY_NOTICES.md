# Third-party software

The app's own code is MIT-licensed (see LICENSE). It is built from the following, all under permissive licenses. The full notices are in `Licenses/` and ship inside the app.

| Component | License | Used for |
|---|---|---|
| [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) 0.14.0 (trimmed copy in `Vendor/SFBAudioEngine`) | MIT | player and decoder framework |
| AVFAudioExtensions, CXXAudioRingBuffer, CXXDispatchSemaphore, CXXMessageQueue, CXXQueue, CXXUnfairLock | MIT | engine utilities |
| libogg, libvorbis | BSD 3-Clause (Xiph.Org) | Ogg Vorbis |
| libopus, opusfile | BSD 3-Clause (Xiph.Org and others) | Opus |
| libFLAC | BSD 3-Clause (Xiph.Org) | FLAC |

MP3, WAV, AIFF, AAC and M4A are decoded by macOS itself (Core Audio).

The app contains no LGPL or GPL code. The audio engine is a reduced copy with the LGPL codec libraries (LAME, mpg123, libsndfile, Musepack, TrueAudio) and everything else the player doesn't use removed; `Vendor/SFBAudioEngine/VENDORED.md` lists exactly what was kept. `scripts/collect-licenses.py` rebuilds `Licenses/` from the packages actually pinned in `Package.resolved`.
