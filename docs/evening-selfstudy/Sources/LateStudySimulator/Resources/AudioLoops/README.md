Built-in real looping ambience files live here.

For quick local testing without rebuilding package resources, you can also place
the same files in:
~/Library/Application Support/LateStudySimulator/AudioLoops

Supported extensions: wav, mp3, m4a, aif, aiff, caf.

Expected base names:
- light_hum
- pen_scratch
- ceiling_fan
- outside_night

If a file is missing, the app falls back to the procedural ambience layer.

Source/provenance:
- Some loops are converted and processed from "100 CC0 SFX 2" on OpenGameArt:
  https://opengameart.org/content/100-cc0-sfx-2
- Classroom-specific loops that were not available as direct matches were
  generated locally with ffmpeg oscillators/noise filters.
- See ../ATTRIBUTION.md for the per-file mapping.
