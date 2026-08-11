Built-in real audio cue files live here.

For quick local testing without rebuilding package resources, you can also place
the same files in:
~/Library/Application Support/LateStudySimulator/AudioCues

Supported extensions: wav, mp3, m4a, aif, aiff, caf.

Expected base names:
- footstep
- paper
- phone
- whisper
- chair
- crying
- lights
- heartbeat
- broadcast
- knock
- stomach
- wrapper
- teacher_cough
- teacher_sigh

If a file is missing, the app falls back to the procedural cue.

Source/provenance:
- Some cues are converted and processed from "100 CC0 SFX 2" on OpenGameArt:
  https://opengameart.org/content/100-cc0-sfx-2
- Classroom-specific cues that were not available as direct matches were generated
  locally with ffmpeg oscillators/noise filters.
- See ../ATTRIBUTION.md for the per-file mapping.
