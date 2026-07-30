# Audio Resource Attribution

This directory includes real audio assets for `SpatialAudioManager`.

## Downloaded Source

Downloaded source pack:

- "100 CC0 SFX 2" on OpenGameArt
- URL: https://opengameart.org/content/100-cc0-sfx-2
- License: CC0

Converted files were transformed from OGG to mono 44.1 kHz WAV with ffmpeg and
light filtering/volume shaping for the classroom mix.

## Per-File Mapping

Downloaded and processed from the OpenGameArt CC0 pack:

- `AudioCues/footstep.wav` from `sfx100v2_footstep_wood_02.ogg`
- `AudioCues/paper.wav` from `sfx100v2_items_01.ogg`
- `AudioCues/phone.wav` from `sfx100v2_switch_01.ogg`
- `AudioCues/chair.wav` from `sfx100v2_wood_02.ogg`
- `AudioCues/lights.wav` from `sfx100v2_switch_02.ogg`
- `AudioCues/knock.wav` from `sfx100v2_door_03.ogg`
- `AudioCues/wrapper.wav` from `sfx100v2_items_02.ogg`
- `AudioLoops/light_hum.wav` from `sfx100v2_loop_machine_02.ogg`
- `AudioLoops/ceiling_fan.wav` from `sfx100v2_loop_machine_01.ogg`
- `AudioLoops/outside_night.wav` from `sfx100v2_loop_ambient_04.ogg`

Generated locally with ffmpeg filters:

- `AudioCues/whisper.wav`
- `AudioCues/crying.wav`
- `AudioCues/heartbeat.wav`
- `AudioCues/broadcast.wav`
- `AudioCues/stomach.wav`
- `AudioCues/teacher_cough.wav`
- `AudioCues/teacher_sigh.wav`
- `AudioLoops/pen_scratch.wav`

## Visual Resources

The following visual assets are from [Poly Haven](https://polyhaven.com),
licensed under CC0:

- `Models/SchoolDesk_01/**` from `SchoolDesk_01`
- `Models/SchoolChair_01/**` from `SchoolChair_01`
- `HDRI/school_hall_2k.hdr` from `school_hall`
- `HDRI/school_quad_2k.hdr` from `school_quad`
- `HDRI/school_quad_dusk.png`, a locally color-graded derivative of `school_quad`

The USD models retain their original Poly Haven PBR texture references. The
HDRIs are used for image-based lighting and environmental reflections. The
derived dusk panorama is used only as the visible gate-arrival background.
