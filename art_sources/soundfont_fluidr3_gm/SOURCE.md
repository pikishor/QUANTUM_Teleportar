# FluidR3 GM SoundFont (Frank Wen), used to render the game's MIDI music

- What: `FluidR3_GM.sf2` (General MIDI instrument samples: pads, strings, choir, brass, piano, harp, guitars, basses, drum kits).
- Author: Frank Wen (with the contributors listed in LICENSE.txt). Upstream: https://musescore.org/download/fluid-soundfont.tar.gz (the MuseScore copy).
- Licence: MIT ("I hereby release Fluid under the MIT license"), the full text is in LICENSE.txt (the Debian package's copyright file, which quotes the README and the MIT text).
  MIT permits use, modification and redistribution of the SoundFont and of audio rendered from it, with the notice kept. Credit is given in docs/THIRD_PARTY.md and docs/AUDIO_SOURCES.md.
- Where it came from here: the Ubuntu package `fluid-soundfont-gm` (installed with `apt-get install fluidsynth fluid-soundfont-gm`, file /usr/share/sounds/sf2/FluidR3_GM.sf2, 148 MB).
- The SoundFont itself is NOT committed (148 MB). Only the rendered, size-reduced OGG stems (about 7 MB), the MIDI sources (tools/music/midi, 208 KB) and the composer (tools/music/compose.py) are.
- Renderer: FluidSynth (LGPL-2.1+) as a tool through pyfluidsynth; nothing of FluidSynth is shipped in the game.
