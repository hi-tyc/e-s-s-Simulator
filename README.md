# Modern School Campus Blender Prototype

This branch contains generated Blender assets for a modern, technology-oriented school prototype. It now includes both:

- `school_campus.blend`: full campus map prototype.
- `classroom.blend`: detailed 55-seat smart classroom prototype.

The campus style is reconstructed from public descriptions and images of Nanjing Foreign Language School Fangshan Campus: red brick and warm white stone, a semi-open entrance academy court, north-south ceremonial axis, east-west learning street, central water/courtyard space, courtyard teaching clusters, separated quiet/active zones, sports facilities, living facilities, and a technology/STEM emphasis. This is a public-source high-similarity reconstruction prototype, not a real security, MEP, or restricted construction drawing.

Reference links:

- https://www.archdaily.cn/cn/934588/nan-jing-wai-guo-yu-xue-xiao-fang-shan-xiao-qu-glajian-zhu-she-ji
- https://www.archdaily.cn/cn/934588/nan-jing-wai-guo-yu-xue-xiao-fang-shan-xiao-qu-glajian-zhu-she-ji/5e586dec6ee67e38150000bc-nan-jing-wai-guo-yu-xue-xiao-fang-shan-xiao-qu-glajian-zhu-she-ji-ping-mian-tu
- https://www.gla.com.cn/product/49.html
- https://www.archcollege.com/47000.html
- https://www.sinodea.com/alzs/alxq.aspx?id=93&mtt=s

## Files

- `build_school_campus.py`: builds the complete campus map and preview images.
- `append_fangshan_public_layers.py`: opens an existing campus `.blend`, appends the public-reference reconstruction and gameplay interaction layers, then regenerates campus previews.
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
- Culture/arts/student center: black-box theater, small stage, choir and dance rehearsal, instrument and costume storage, gallery, ceramics studio, campus radio, TV studio, recording room, media editing, student union, club rooms, media release screen, display corridor, club fair plaza, culture wall, flag ceremony court, motto stone, and activity information screen.
- Transport/accessibility operations: parent quick drop-off, waiting canopy, student queue buffer, visitor drop-off, bus canopy, shared-bike parking, pedestrian/bus/parent/bike/logistics/accessibility flow layers, accessible elevator entries, accessible toilet, tactile paving nodes, traffic guidance screens, parking availability display, flow detector, violation camera, logistics reservation terminal, and emergency vehicle staging.
- MEP/building operations: power feeders, fiber ring, fire water, domestic water, chilled water, rainwater reuse, sewage drainage, kitchen gas line, electrical/low-voltage/plumbing risers, rooftop AHUs, smoke exhaust, kitchen exhaust, roof tank, fire pressure tank, elevator machine rooms, BMS sensors, utility-gallery environmental sensors, sump pump pit, and ventilation shaft.
- Campus governance operations: integrated operations center, school-data dashboard, timetable/bell control, academic calendar board, class schedule screens, exam-security room, grade analytics, asset repair tickets, duty roster, patrol checkpoints, visitor/vehicle appointments, campus card and navigation terminals, health reporting, lab/venue/meeting reservations, dormitory late-return check-in, canteen staggered dining, family-school notice publishing, and cross-campus data bus.
- Foreign-language and international-exchange learning center: simultaneous-interpretation lab, multilingual listening/speaking pods, Model United Nations classroom, debate classroom, foreign-teacher office, international-exchange office, overseas advising, IELTS/TOEFL computer-test room, minor-language resource library, original-language reading corner, sister-school video room, AI speaking booth, cross-cultural workshop, English-drama rehearsal, diplomatic reception room, exchange-student service desk, culture flag corridor, international-week booths, and international-course walking routes.
- Surrounding city/municipal interface: external arterial road, slow-mobility greenway, sidewalks, zebra crossing, pedestrian refuge, speed table, bus stop, ride-hailing drop-off, metro-connection wayfinding, bike waiting zone, traffic signals, student crossing buttons, external traffic cameras/radar, municipal water/electric/telecom/gas/sewage/fire-water handoff boxes, city-to-campus utility tie-ins, Fangshan ecological buffer, viewing platform, and surrounding-interface overview board.
- Night/weather resilience operations: smart streetlights, bollard courtyard lights, stadium floodlights, facade wash lights, dormitory night windows and check-in screens, drainage grates, waterlogging sensors, storm overflow routes, rooftop lightning rods, thunderstorm warning screen, heat refuge point, rain/snow anti-slip supply box, extreme-weather class-suspension screen, lighting control loops, and weather/waterlogging alarm data lines.
- Wireless network and edge-computing operations: campus Wi-Fi AP coverage disks, edge-computing boxes, IoT gateways, core switch, next-generation firewall, NAC controller, security log/audit screen, backup appliance, NTP clock server, unified campus clock screens, IP broadcast terminals, AP controller links, IoT aggregation links, and security-log return route.
- Complete building-interior coverage: every major building mass has visible interior floor plates, corridors, room programs, furniture/equipment blocks, and facility index markers, covering the guard room, library/administration, STEM, liberal-arts center, four teaching clusters, technology operations building, indoor sports hall, canteen, dormitory/living group, clinic/counseling center, and foreign-language exchange center.
- Main gameplay teaching building: the high-school teaching cluster is modeled as a four-floor detailed interior with wide corridor depth, floor plates, classroom props, smart boards, class boards, desks/chairs, lockers, toilets with male/female/accessible zones, sinks, mirrors, west/east stair cores, elevator hall, fire hydrants, exit signs, floor wayfinding, and a main-scene overview board.
- Gameplay navigation/interaction layer for the main teaching building: player spawn point, quest/check/save points, interactive door markers, passable corridor paths, stair/elevator vertical links, and explicit collision/boundary guide markers.
- Fangshan public-reference reconstruction layer: visible source panels, plan-control frame, north-south and east-west axes, center water court, semi-open entrance ring control line, public-plan district bands, red-brick/warm-stone facade markers, courtyard learning clusters, shared-learning-street glass facades, and public-feature callouts.
- Fangshan high-similarity public-detail layer: public-keyword panels for Xueyuan Fangcheng, third-generation school, public-school campus style, four school divisions, and interior deepening; elementary/middle/high/international-high division markers; south city-facing red-brick facade bands with vertical window openings; staggered roof-height cues; non-formal learning steps with discussion screens; and interior-deepening cues for teaching, comprehensive, and living buildings.
- Fangshan public curriculum/courtyard detail layer: courtyard-arch cues, A-Level/AP/OSSD international-course rooms, international advising, English-drama and cross-cultural display spaces, arts and science-competition rooms, residential-college house lounges, and four-division curriculum map boards.

The campus verifier checks the generated `.blend` for required facilities and verifies that at least 32 numbered campus preview images plus the overview contact sheet exist.

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
/snap/blender/current/blender -b school_campus.blend --python append_fangshan_public_layers.py
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
