# Modern School Campus Blender Prototype

This branch contains generated Blender assets for a modern, technology-oriented school prototype. It now includes both:

- `school_campus.blend`: full campus map prototype.
- `classroom.blend`: detailed 55-seat smart classroom prototype.

The campus style is inspired by public descriptions of Nanjing Foreign Language School Fangshan Campus: red brick and warm white stone, courtyard learning clusters, a semi-open entrance ring, central water/courtyard space, separated quiet/active zones, sports facilities, living facilities, and a technology/STEM emphasis. This is a public-facing conceptual prototype, not a real security, MEP, or restricted campus drawing.

Reference links:

- https://www.archdaily.cn/cn/936437/nan-jing-wai-guo-yu-xue-xiao-fang-shan-xiao-qu-zhu-jing-she-ji
- https://www.gla.com.cn/en/index.php/works/nanjing-foreign-language-school-fangshan-campus/

## Files

- `build_school_campus.py`: builds the complete campus map and preview images.
- `verify_school_campus.py`: verifies required campus facilities exist in `school_campus.blend`.
- `school_campus.blend`: generated complete campus scene.
- `campus_previews/`: exported campus preview images and `00_校园总览拼图.png`.
- `build_modern_classroom.py`: rebuilds the detailed classroom scene.
- `render_classroom_views.py`: renders classroom preview images.
- `classroom.blend`: generated classroom scene.
- `previews/`: exported classroom preview images and `00_总览拼图.png`.
- `test_text_orientation.py`: helper used to verify text orientation on vertical boards.

## Campus Coverage

The full campus scene includes:

- Main gate and guard room.
- Security turnstiles and CCTV points.
- Monitoring room with video wall and operator desks.
- Technology operations building.
- Microcomputer classroom.
- Server room / machine room.
- Distribution room and outdoor transformer yard.
- STEM center, library/administration center, liberal arts center.
- Multiple teaching courtyard clusters and classroom groups.
- Central reflecting pond and courtyard axes.
- Outdoor track and football field.
- Indoor sports hall / indoor playground.
- Basketball courts.
- Canteen, dormitory/living group, clinic/counseling center.
- Campus fiber backbone, power backbone, smart light poles.
- Service energy/generator zone.
- Physics, chemistry, biology, AI maker, VR, robotics, language, art, music, school-history, teacher-development, and parent-reception spaces.
- Dining, dormitory, indoor sports, and teaching-building cutaway interiors.
- Toilets, elevators, stair cores, access-control nodes.
- Campus boundary walls, ring fire lane, loading dock, waste sorting station.
- Bus drop-off, bike parking, accessible ramp.
- Fire hydrants, evacuation routes, assembly areas, broadcast speakers.
- Underground utility gallery with inspection manholes.
- Weather station and air-quality sensor.
- Library interior reading area, shelves, and self-checkout kiosk.
- Sports support rooms: changing room, shower room, equipment room, referee/medical point.
- Wayfinding screens, AED boxes, emergency phones, drinking water points, lockers, electronic class boards, visitor terminal, and charging station.

## Classroom Coverage

The detailed classroom scene includes:

- 55-seat large classroom, four paired-desk groups.
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
/snap/blender/current/blender -b --python build_school_campus.py
/snap/blender/current/blender -b school_campus.blend --python verify_school_campus.py
/snap/blender/current/blender -b --python build_modern_classroom.py
/snap/blender/current/blender -b --python render_classroom_views.py
```

Optional campus environment variables:

- `SCHOOL_ROOT`: output directory.
- `SCHOOL_BLEND`: campus `.blend` path.
- `SCHOOL_PREVIEW_DIR`: campus preview image output directory.

Optional classroom environment variables:

- `CLASSROOM_ROOT`: output directory.
- `CLASSROOM_BLEND`: classroom `.blend` path.
- `CLASSROOM_PREVIEW_DIR`: classroom preview image output directory.
