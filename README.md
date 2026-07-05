# Modern Classroom Blender Scene

This branch contains the generated Blender classroom scene and the Python scripts used to rebuild it.

## Files

- `classroom.blend`: generated Blender scene.
- `build_modern_classroom.py`: rebuilds the full classroom scene into `教室.blend` when run from the desktop workspace.
- `render_classroom_views.py`: renders the preview images from the generated `.blend`.
- `test_text_orientation.py`: small helper used to verify Blender text orientation on vertical boards.
- `previews/`: exported preview images, including `00_总览拼图.png`.

## Scene Contents

- 55-seat large classroom.
- Four student desk groups with paired desks.
- Books placed inside desk drawers instead of on desktops.
- Front teaching platform with center blackboard and two side touchscreens.
- Embedded podium computer, side IO bay, USB/USB-C/DP/HDMI/LAN details.
- Wiring represented as wall-hidden conduits and floor/platform cable trenches.
- Rear class blackboard newspaper wall.
- LED lights, ceiling fans, wall-mounted air conditioners, wall switches, thermostat controls.
- Day/night window modes with exterior roads, trees, buildings, moon, and lit windows.
- Air conditioner outdoor condenser units with refrigerant/drain lines through the wall.

## Regeneration

From this branch root:

```bash
/snap/blender/current/blender -b --python build_modern_classroom.py
/snap/blender/current/blender -b --python render_classroom_views.py
```

Optional environment variables:

- `CLASSROOM_ROOT`: output directory.
- `CLASSROOM_BLEND`: `.blend` path.
- `CLASSROOM_PREVIEW_DIR`: preview image output directory.
