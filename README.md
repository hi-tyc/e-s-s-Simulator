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
- District overlays for entrance/shared, teaching quiet, sports, living/logistics, and technology operations zones.
- Additional logistics/emergency gates, visitor parking, and staff parking.
- Fire hydrants, evacuation routes, assembly areas, broadcast speakers.
- Underground utility gallery with inspection manholes.
- Weather station and air-quality sensor.
- Library interior reading area, shelves, and self-checkout kiosk.
- Administration cutaway with principal office, academic affairs, general affairs, finance, meeting, and archive rooms.
- Lab safety equipment: chemical storage, hazardous waste box, fume hood, emergency shower/eyewash, and biosafety cabinet.
- Campus HVAC/water/fire service nodes: energy station, chiller, circulation pump, fire tank, pump rooms, IDF closets, BAS, day/night mode, and lighting circuit control.
- Athletics support: spectator stand, rostrum, electronic scoreboard, long-jump pit, and shot-put area.
- Outdoor learning landscape: amphitheater, reading garden, ecological wetland, labor-education garden, and greenhouse.
- Sports support rooms: changing room, shower room, equipment room, referee/medical point.
- Wayfinding screens, AED boxes, emergency phones, drinking water points, lockers, electronic class boards, visitor terminal, and charging station.
- Map delivery aids: coordinate grid, north arrow, scale bar, building ID tags, floor-function boards, route layers, system overview boards, CCTV coverage disks, and electronic layer-control console.
- Teaching-detail layer: grade-zone boards, classroom room numbers, teacher offices, preparation rooms, grade offices, storage rooms, covered corridors, a capacity schedule board, and an embedded 55-seat smart-classroom cutaway with four paired-desk groups.
- Living/logistics operations: canteen receiving, cold/dry storage, rough processing, cooking, serving, dishwashing/disinfection, retained-sample cabinet, food-safety screen, dorm sample rooms, bathrooms, shower, laundry, study, houseparent, logistics storage, repair workshop, cold-chain bay, kitchen-waste cold box, and fume purification.
- Sports-health system: indoor basketball, volleyball, badminton, table tennis, fitness, dance/yoga, body-test zone, retractable stand, scoreboard, sports AED/medical point, outdoor volleyball/tennis/fitness/calisthenics zones, PE office, equipment issue, injury treatment, and night-running lights.
- Safety-resilience layer: perimeter intrusion detection, visitor/vehicle verification, patrol checkpoints, fire alarm call points, smoke detectors, emergency lighting, fire shutters, alarm/security linkage panels, emergency supplies, shelter tents, satellite communications, emergency wireless base station, UPS, battery storage, microgrid switchgear, emergency water purification, and command center.
- Low-carbon science operations: PV inverters, combiner boxes, carbon/energy dashboard, submetering, EV and school-bus charging, rainwater reuse, reclaimed-water treatment, permeable paving sample, smart irrigation, soil moisture, water quality, biodiversity plot, insect hotel, bird observation, rooftop greening, heat-island/noise monitoring, microclimate tower, and operations digital twin board.

The campus verifier checks the generated `.blend` for required facilities and verifies that at least 18 numbered campus preview images plus the overview contact sheet exist.

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
