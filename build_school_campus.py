import math
import os
import subprocess

import bpy
from mathutils import Vector


ROOT = os.environ.get("SCHOOL_ROOT", os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.environ.get("SCHOOL_BLEND", os.path.join(ROOT, "school_campus.blend"))
PREVIEW_DIR = os.environ.get("SCHOOL_PREVIEW_DIR", os.path.join(ROOT, "campus_previews"))


MATS = {}


def mat(name, color, roughness=0.55, metallic=0.0, alpha=1.0, emission=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Alpha"].default_value = alpha
        if emission:
            bsdf.inputs["Emission Color"].default_value = emission
            bsdf.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = color
    if alpha < 1:
        m.blend_method = "BLEND"
        m.show_transparent_back = True
    return m


def init_materials():
    MATS.update(
        {
            "grass": mat("campus lawn", (0.12, 0.42, 0.17, 1), 0.75),
            "track": mat("red rubber track", (0.62, 0.14, 0.08, 1), 0.65),
            "field": mat("synthetic sports field", (0.05, 0.45, 0.18, 1), 0.62),
            "road": mat("quiet asphalt service road", (0.1, 0.105, 0.11, 1), 0.7),
            "paving": mat("warm stone campus paving", (0.68, 0.63, 0.55, 1), 0.55),
            "water": mat("central reflecting water", (0.16, 0.47, 0.68, 0.72), 0.08, alpha=0.72),
            "brick": mat("NFLS inspired dark red brick", (0.46, 0.12, 0.08, 1), 0.58),
            "stone": mat("warm white stone", (0.86, 0.82, 0.72, 1), 0.48),
            "roof": mat("dark standing seam roof", (0.08, 0.085, 0.09, 1), 0.42),
            "glass": mat("blue low-e glass", (0.42, 0.67, 0.82, 0.45), 0.12, alpha=0.45),
            "screen": mat("active display panels", (0.02, 0.08, 0.12, 1), 0.25, emission=(0.02, 0.36, 0.55, 1), strength=0.65),
            "panel": mat("matte black equipment panel", (0.025, 0.028, 0.032, 1), 0.5),
            "metal": mat("dark anodized metal", (0.18, 0.19, 0.19, 1), 0.32, metallic=0.35),
            "white": mat("satin white equipment", (0.88, 0.89, 0.86, 1), 0.42),
            "yellow": mat("safety yellow utility", (0.95, 0.68, 0.12, 1), 0.5),
            "orange": mat("orange wayfinding accent", (0.88, 0.34, 0.08, 1), 0.52),
            "blue": mat("network blue", (0.03, 0.2, 0.78, 1), 0.44),
            "purple": mat("science purple", (0.34, 0.22, 0.55, 1), 0.55),
            "green": mat("laboratory safety green", (0.1, 0.55, 0.32, 1), 0.55),
            "red": mat("fire safety red", (0.72, 0.04, 0.03, 1), 0.48),
            "solar": mat("blue black solar glass", (0.01, 0.035, 0.08, 1), 0.18, emission=(0.0, 0.04, 0.08, 1), strength=0.15),
            "parking": mat("parking line white", (0.93, 0.93, 0.86, 1), 0.55),
            "wetland": mat("rain garden wetland", (0.08, 0.28, 0.2, 1), 0.8),
            "wood": mat("warm indoor wood", (0.55, 0.34, 0.16, 1), 0.52),
            "tree": mat("campus tree canopy", (0.04, 0.34, 0.12, 1), 0.7),
            "trunk": mat("tree trunk bark", (0.38, 0.22, 0.1, 1), 0.8),
            "light": mat("warm architectural light", (1, 0.92, 0.7, 1), 0.2, emission=(1, 0.82, 0.46, 1), strength=1.0),
            "mountain": mat("fangshan green ridge backdrop", (0.13, 0.27, 0.15, 1), 0.8),
        }
    )


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for data in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for block in list(data):
            if block.users == 0:
                data.remove(block)


def cube(name, loc, size, material=None, bevel=0.0, rot_z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(0, 0, rot_z))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material:
        obj.data.materials.append(material)
    if bevel:
        b = obj.modifiers.new("softened edges", "BEVEL")
        b.width = bevel
        b.segments = 2
        obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    return obj


def cyl(name, loc, radius, depth, material=None, vertices=32, rot=(0, 0, 0), bevel=False):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    if bevel:
        b = obj.modifiers.new("soft rim", "BEVEL")
        b.width = min(radius * 0.18, 0.08)
        b.segments = 3
        obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    try:
        bpy.ops.object.shade_smooth()
    except Exception:
        pass
    return obj


def text(name, body, loc, size=1.0, material=None, rot=(0, 0, 0), align="CENTER"):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = body
    obj.data.align_x = align
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.02
    if material:
        obj.data.materials.append(material)
    return obj


def building(name, x, y, w, d, h, label, floors=3, accent=None):
    base = cube(f"{name} red-brick mass", (x, y, h / 2), (w, d, h), MATS["brick"], 0.18)
    cube(f"{name} warm stone base", (x, y, 0.25), (w + 0.4, d + 0.4, 0.5), MATS["stone"], 0.08)
    cube(f"{name} dark roof", (x, y, h + 0.15), (w + 0.25, d + 0.25, 0.3), MATS["roof"], 0.08)
    for f in range(floors):
        z = 1.0 + f * (h - 1.3) / max(1, floors - 1)
        for wx in [-w / 2 - 0.03, w / 2 + 0.03]:
            cube(f"{name} side window floor {f} {wx}", (x + wx, y, z), (0.05, d * 0.74, 0.34), MATS["glass"], 0.01)
        for wy in [-d / 2 - 0.03, d / 2 + 0.03]:
            cube(f"{name} facade window floor {f} {wy}", (x, y + wy, z), (w * 0.7, 0.05, 0.34), MATS["glass"], 0.01)
    if accent:
        cube(f"{name} colored program marker", (x, y - d / 2 - 0.08, h * 0.55), (w * 0.55, 0.08, 0.28), accent, 0.02)
    text(f"{name} roof label", label, (x, y, h + 0.42), 0.75, MATS["white"], rot=(0, 0, 0))
    return base


def semicircle_ring():
    center = (0, -45)
    radius = 24
    for i, angle in enumerate(range(205, 336, 13)):
        rad = math.radians(angle)
        x = center[0] + math.cos(rad) * radius
        y = center[1] + math.sin(rad) * radius
        cube(f"semi-open entrance ring segment {i}", (x, y, 2.2), (6.2, 3.8, 4.4), MATS["brick"], 0.14, rot_z=rad + math.pi / 2)
    text("entrance ring label", "半敞开入口艺苑 / STEM·图书·行政", (0, -64, 0.08), 1.4, MATS["white"], rot=(0, 0, 0))
    cyl("entrance circular court paving", (0, -45, 0.025), 22, 0.05, MATS["paving"], vertices=96)
    cyl("entrance circular court inner lawn", (0, -45, 0.08), 11, 0.08, MATS["grass"], vertices=96)


def add_tree(x, y, scale=1.0, name="tree"):
    cyl(f"{name} trunk", (x, y, 0.6 * scale), 0.12 * scale, 1.2 * scale, MATS["trunk"], vertices=10)
    cyl(f"{name} canopy", (x, y, 1.45 * scale), 0.55 * scale, 0.5 * scale, MATS["tree"], vertices=18, bevel=True)


def add_security_camera(name, x, y, z, rot_z=0):
    cyl(f"{name} pole", (x, y, z - 0.5), 0.06, 1.0, MATS["metal"], vertices=12)
    cam = cube(f"{name} camera body", (x, y, z + 0.08), (0.45, 0.18, 0.18), MATS["white"], 0.03, rot_z=rot_z)
    cube(f"{name} black lens", (x + math.cos(rot_z) * 0.25, y + math.sin(rot_z) * 0.25, z + 0.08), (0.08, 0.08, 0.08), MATS["panel"], 0.02, rot_z=rot_z)
    return cam


def make_campus_base():
    cube("full campus site base", (0, 0, -0.06), (150, 110, 0.12), MATS["grass"], 0.04)
    cube("main north south axis paving", (0, -3, 0.02), (7.5, 96, 0.05), MATS["paving"], 0.03)
    cube("east west learning axis paving", (0, -8, 0.03), (112, 6, 0.05), MATS["paving"], 0.03)
    cyl("central reflecting pond", (0, -2, 0.09), 8, 0.05, MATS["water"], vertices=80)
    for r, y in [(18, 41), (22, 47), (28, 53)]:
        cube(f"fangshan ridge layer {r}", (0, y, 1.1 + (r - 18) * 0.04), (150, 5.5, 2.0), MATS["mountain"], 0.35)
    cube("south city road", (0, -56, 0.03), (150, 8, 0.06), MATS["road"], 0.03)
    cube("campus front plaza", (0, -49.5, 0.06), (42, 13, 0.06), MATS["paving"], 0.03)
    for x in [-65, -55, -45, 45, 55, 65]:
        add_tree(x, -49, 1.2, f"front street tree {x}")
    for x in range(-62, 63, 8):
        add_tree(x, 31, 0.8, f"north shelterbelt tree {x}")


def make_gate_and_security():
    cube("main gate arch left pier", (-7, -57.2, 2.1), (1.1, 2.0, 4.2), MATS["brick"], 0.08)
    cube("main gate arch right pier", (7, -57.2, 2.1), (1.1, 2.0, 4.2), MATS["brick"], 0.08)
    cube("main gate lintel", (0, -57.2, 4.1), (15.3, 1.5, 0.8), MATS["stone"], 0.08)
    text("school gate name", "南京外国语学校 · 智慧校园原型", (0, -58.05, 4.35), 0.7, MATS["brick"], rot=(math.radians(90), 0, 0))
    cube("guard room security office", (-14, -53.2, 1.4), (5.5, 4.2, 2.8), MATS["brick"], 0.12)
    cube("guard room glass window", (-14, -55.35, 1.65), (4.2, 0.06, 1.15), MATS["glass"], 0.02)
    text("guard room label", "保安室", (-14, -53.2, 3.1), 0.65, MATS["white"])
    cube("visitor turnstile row", (0, -52.0, 0.55), (7.2, 0.7, 1.1), MATS["metal"], 0.04)
    for x in [-2.5, 0, 2.5]:
        cube(f"face recognition gate {x}", (x, -52.5, 1.15), (0.55, 0.2, 1.2), MATS["screen"], 0.03)
    add_security_camera("gate CCTV 1", -5, -52, 3.2, rot_z=-math.pi / 2)
    add_security_camera("gate CCTV 2", 5, -52, 3.2, rot_z=-math.pi / 2)


def make_academic_core():
    semicircle_ring()
    building("library administration center", 0, -21, 16, 9, 5.2, "图书馆/行政中心", floors=3, accent=MATS["orange"])
    building("STEM center", -23, -24, 13, 8, 4.8, "STEM中心", floors=3, accent=MATS["purple"])
    building("liberal arts center", 23, -24, 13, 8, 4.8, "博雅中心", floors=3, accent=MATS["blue"])
    for idx, (x, y, label) in enumerate([(-38, 4, "初中教学组团"), (-12, 12, "高中教学组团"), (14, 12, "国际部教学组团"), (40, 4, "小学/共享教室组团")]):
        building(f"teaching courtyard {idx}", x, y, 17, 12, 4.8, label, floors=3, accent=MATS["stone"])
        cyl(f"teaching courtyard {idx} inner courtyard", (x, y, 0.1), 4.2, 0.06, MATS["paving"], vertices=48)
        add_tree(x - 2.2, y + 1.2, 0.75, f"{label} courtyard tree a")
        add_tree(x + 2.2, y - 1.0, 0.75, f"{label} courtyard tree b")


def make_room_equipment(x, y, name):
    cube(f"{name} raised technical floor", (x, y, 0.18), (20, 12, 0.2), MATS["metal"], 0.04)
    cube(f"{name} room outline", (x, y, 1.2), (20.4, 12.4, 2.2), MATS["glass"], 0.04)
    text(f"{name} roof label", name, (x, y, 2.48), 0.7, MATS["white"])


def make_technology_building():
    building("technology and operations building", -48, -21, 24, 15, 4.4, "科技运维楼", floors=2, accent=MATS["blue"])
    # Exposed room map beside/inside the technology block.
    make_room_equipment(-57, -22, "微机室")
    for row in range(3):
        for col in range(6):
            cube(f"computer lab desk {row}-{col}", (-64 + col * 2.4, -25 + row * 2.4, 0.72), (1.5, 0.7, 0.08), MATS["white"], 0.04)
            cube(f"computer lab monitor {row}-{col}", (-64 + col * 2.4, -25.32 + row * 2.4, 1.03), (0.62, 0.08, 0.42), MATS["screen"], 0.02)
    make_room_equipment(-36, -22, "服务器机房")
    for i in range(6):
        cube(f"server rack {i}", (-42 + i * 2.2, -22, 1.2), (0.9, 1.2, 2.1), MATS["panel"], 0.04)
        cube(f"server rack blue led {i}", (-42 + i * 2.2, -22.62, 1.4), (0.5, 0.05, 1.3), MATS["blue"], 0.01)
    make_room_equipment(-57, -7, "配电室")
    for i, x in enumerate([-63, -60, -57, -54, -51]):
        cube(f"distribution cabinet {i}", (x, -7, 1.2), (1.0, 1.1, 2.0), MATS["yellow"], 0.04)
        cube(f"distribution cabinet warning {i}", (x, -7.58, 1.55), (0.42, 0.04, 0.35), MATS["panel"], 0.01)
    make_room_equipment(-36, -7, "监控室")
    cube("monitoring video wall", (-36, -12.9, 1.45), (8.8, 0.1, 1.8), MATS["screen"], 0.03)
    for i in range(4):
        cube(f"monitoring operator desk {i}", (-41 + i * 3.2, -6, 0.72), (2.0, 0.85, 0.08), MATS["white"], 0.04)
        cube(f"monitoring console screen {i}", (-41 + i * 3.2, -6.42, 1.05), (0.75, 0.08, 0.45), MATS["screen"], 0.02)
    # Campus fiber and power routes.
    cube("blue fiber backbone trench", (-18, -7, 0.12), (50, 0.34, 0.08), MATS["blue"], 0.02)
    cube("yellow power backbone trench", (-18, -9, 0.13), (50, 0.34, 0.08), MATS["yellow"], 0.02)
    text("backbone label", "蓝=校园光纤 / 黄=电力主干", (-18, -10.2, 0.12), 0.65, MATS["white"])


def make_science_and_innovation_spaces():
    # STEM building exposed program bands.
    lab_specs = [
        ("物理实验室", -27.8, -29.4, MATS["blue"]),
        ("化学实验室", -23.0, -29.4, MATS["green"]),
        ("生物实验室", -18.2, -29.4, MATS["purple"]),
        ("AI创客工坊", -27.8, -18.8, MATS["orange"]),
        ("VR沉浸教室", -23.0, -18.8, MATS["screen"]),
        ("机器人社团", -18.2, -18.8, MATS["yellow"]),
    ]
    for name, x, y, color in lab_specs:
        cube(f"设施索引_{name}", (x, y, 0.36), (1.0, 1.0, 0.58), color, 0.04)
        cube(f"{name} glass lab bay", (x, y, 1.1), (4.0, 3.0, 1.8), MATS["glass"], 0.04)
        cube(f"{name} lab bench", (x, y, 0.86), (2.7, 0.62, 0.12), MATS["white"], 0.03)
        cube(f"{name} equipment wall", (x, y + 1.36, 1.25), (2.8, 0.12, 1.0), color, 0.02)
        text(f"{name} label", name, (x, y, 2.15), 0.38, MATS["white"])
    for i, x in enumerate([-29.2, -26.3, -23.4, -20.5, -17.6]):
        cyl(f"STEM roof observatory telescope {i}", (x, -24, 5.25), 0.09, 1.1, MATS["metal"], vertices=18, rot=(0, math.radians(70), 0))
    cube("设施索引_报告厅", (23, -16, 0.36), (1.0, 1.0, 0.58), MATS["orange"], 0.04)
    cube("auditorium stepped seating block", (23, -16, 0.55), (11.5, 5.5, 0.7), MATS["brick"], 0.08)
    for i in range(5):
        cube(f"auditorium seating tier {i}", (23, -18 + i * 0.85, 0.75 + i * 0.08), (10.8, 0.28, 0.12), MATS["orange"], 0.02)
    cube("auditorium presentation screen", (23, -12.9, 1.7), (6.2, 0.08, 1.6), MATS["screen"], 0.03)


def make_transport_and_access():
    cube("school bus dropoff lane", (-31, -55.4, 0.09), (38, 2.2, 0.08), MATS["road"], 0.04)
    cube("设施索引_校车落客区", (-31, -55.4, 0.42), (1.0, 1.0, 0.62), MATS["orange"], 0.04)
    for i, x in enumerate([-43, -35, -27, -19]):
        cube(f"school bus bay marking {i}", (x, -55.4, 0.16), (5.2, 0.1, 0.025), MATS["parking"], 0.004)
        cube(f"school bus placeholder {i}", (x, -53.8, 0.72), (4.8, 1.25, 1.1), MATS["yellow"], 0.08)
        cube(f"school bus windshield {i}", (x + 1.75, -53.1, 0.92), (0.6, 0.05, 0.45), MATS["glass"], 0.01)
    cube("bike parking shelter roof", (31, -53.5, 2.1), (17, 3.5, 0.22), MATS["roof"], 0.06)
    cube("设施索引_自行车停车棚", (31, -53.5, 0.42), (1.0, 1.0, 0.62), MATS["orange"], 0.04)
    for i, x in enumerate(range(24, 39, 2)):
        cyl(f"bike parking rack {i}", (x, -53.5, 0.45), 0.08, 1.0, MATS["metal"], vertices=12, rot=(math.radians(90), 0, 0))
    cube("accessible ramp at main gate", (9.5, -50.1, 0.12), (7.0, 1.6, 0.12), MATS["paving"], 0.04, rot_z=math.radians(-8))
    cube("设施索引_无障碍坡道", (9.5, -50.1, 0.42), (1.0, 1.0, 0.62), MATS["orange"], 0.04)
    text("transport label", "校车落客 / 自行车棚 / 无障碍坡道", (0, -61.5, 0.15), 0.75, MATS["white"])


def make_smart_safety_energy_systems():
    for i, (x, y, w, d) in enumerate([(0, -21, 14, 7), (-23, -24, 11, 6), (55, 11, 18, 11), (54, 31, 22, 7)]):
        for sx in [-0.35, 0, 0.35]:
            cube(f"solar roof array {i}-{sx}", (x + sx * w, y, 5.75 if i != 2 else 7.75), (w * 0.24, d * 0.72, 0.08), MATS["solar"], 0.02)
    cyl("rainwater collection tank north", (-72, 39, 1.0), 1.2, 2.0, MATS["water"], vertices=32, bevel=True)
    cube("rain garden bioswale", (-46, 41, 0.08), (38, 3.2, 0.08), MATS["wetland"], 0.08)
    text("sponge campus label", "海绵校园：雨水花园 / 回收水罐 / 太阳能屋顶", (-46, 43.3, 0.18), 0.6, MATS["white"])
    for i, (x, y) in enumerate([(-40, 20), (-12, 27), (14, 27), (41, 20), (0, -31), (52, -1), (54, 23)]):
        cube(f"fire hydrant cabinet {i}", (x, y, 0.55), (0.55, 0.28, 1.05), MATS["red"], 0.03)
        cyl(f"fire hydrant hose reel {i}", (x, y - 0.16, 0.7), 0.18, 0.035, MATS["white"], vertices=24, rot=(math.radians(90), 0, 0))
    for i, (x1, y1, x2, y2) in enumerate([(-38, 4, -22, -6), (-12, 12, 0, -2), (14, 12, 0, -2), (40, 4, 23, -6), (55, 11, 45, -28)]):
        cube(f"evacuation route arrow body {i}", ((x1 + x2) / 2, (y1 + y2) / 2, 0.2), (abs(x2 - x1) + 0.8, 0.24, 0.05), MATS["red"], 0.01, rot_z=math.atan2(y2 - y1, x2 - x1))
        cyl(f"evacuation route arrow head {i}", (x2, y2, 0.24), 0.42, 0.08, MATS["red"], vertices=3, rot=(0, 0, math.atan2(y2 - y1, x2 - x1) - math.pi / 2))
    cube("campus broadcast control cabinet", (-36, -2.5, 0.72), (1.0, 0.7, 1.2), MATS["panel"], 0.04)
    for i, (x, y) in enumerate([(-30, -15), (0, -15), (30, -15), (-20, 18), (20, 18), (50, -35)]):
        cyl(f"campus broadcast speaker pole {i}", (x, y, 2.0), 0.055, 3.8, MATS["metal"], vertices=12)
        cube(f"campus broadcast speaker {i}", (x, y + 0.32, 3.85), (0.65, 0.28, 0.35), MATS["white"], 0.04)
    cube("campus digital twin operations screen", (-36, -13.05, 2.55), (8.6, 0.09, 0.52), MATS["screen"], 0.02)
    cube("设施索引_数字孪生总控", (-36, -13.05, 3.05), (1.0, 0.2, 0.42), MATS["orange"], 0.03)
    text("digital twin label", "数字孪生总控：安防/能耗/广播/消防/网络", (-36, -13.12, 2.92), 0.35, MATS["light"], rot=(math.radians(90), 0, 0))


def make_cutaway_interiors_and_tunnels():
    # Typical classroom floor plates made readable from the aerial view.
    for b, (cx, cy) in enumerate([(-38, 4), (-12, 12), (14, 12), (40, 4)]):
        cube(f"剖面_教学楼{b}_走廊", (cx, cy, 5.18), (15.5, 1.0, 0.08), MATS["paving"], 0.02)
        for i, ox in enumerate([-5.5, -1.8, 1.8, 5.5]):
            cube(f"剖面_教学楼{b}_普通教室_{i}", (cx + ox, cy + 2.4, 5.25), (2.8, 2.4, 0.12), MATS["white"], 0.02)
            cube(f"剖面_教学楼{b}_智慧黑板_{i}", (cx + ox, cy + 1.18, 5.48), (1.8, 0.08, 0.28), MATS["screen"], 0.01)
            for row in range(2):
                for col in range(2):
                    cube(f"剖面_教学楼{b}_课桌_{i}_{row}_{col}", (cx + ox - 0.55 + col * 1.1, cy + 2.1 + row * 0.55, 5.42), (0.55, 0.32, 0.08), MATS["stone"], 0.01)
        cube(f"剖面_教学楼{b}_教师办公室", (cx - 5.5, cy - 2.2, 5.25), (3.0, 2.2, 0.12), MATS["glass"], 0.02)
        cube(f"剖面_教学楼{b}_楼梯间", (cx + 5.7, cy - 2.2, 5.25), (2.1, 2.1, 0.14), MATS["metal"], 0.02)
        cube(f"设施索引_教学楼{b}_楼层剖面", (cx, cy, 5.65), (1.0, 1.0, 0.35), MATS["orange"], 0.03)

    # Dining hall internals.
    for row in range(3):
        for col in range(5):
            cube(f"食堂餐桌_{row}_{col}", (25.2 + col * 1.9, 28.6 + row * 1.25, 4.55), (1.1, 0.55, 0.1), MATS["white"], 0.02)
            cyl(f"食堂圆凳_{row}_{col}_a", (24.75 + col * 1.9, 28.6 + row * 1.25, 4.33), 0.18, 0.16, MATS["orange"], vertices=18)
            cyl(f"食堂圆凳_{row}_{col}_b", (25.65 + col * 1.9, 28.6 + row * 1.25, 4.33), 0.18, 0.16, MATS["orange"], vertices=18)
    cube("食堂后厨操作间", (34.8, 34.6, 4.55), (6.5, 2.2, 0.18), MATS["metal"], 0.03)
    for i in range(4):
        cube(f"食堂取餐窗口_{i}", (28.5 + i * 1.5, 35.2, 4.85), (1.0, 0.1, 0.42), MATS["screen"], 0.01)
    cube("设施索引_食堂内部剖面", (30, 31, 4.95), (1.0, 1.0, 0.35), MATS["orange"], 0.03)

    # Dormitory room band.
    for i in range(8):
        x = 43.0 + i * 2.9
        cube(f"宿舍房间_{i}", (x, 28.2, 6.05), (2.2, 2.0, 0.14), MATS["white"], 0.02)
        cube(f"宿舍床位_{i}_a", (x - 0.45, 28.2, 6.22), (0.72, 1.55, 0.12), MATS["blue"], 0.02)
        cube(f"宿舍床位_{i}_b", (x + 0.45, 28.2, 6.22), (0.72, 1.55, 0.12), MATS["green"], 0.02)
    cube("宿舍公共洗衣房", (62, 34.8, 6.05), (4.2, 2.0, 0.14), MATS["glass"], 0.02)
    cube("设施索引_宿舍内部剖面", (54, 31, 6.55), (1.0, 1.0, 0.35), MATS["orange"], 0.03)

    # Indoor sports hall markings.
    cube("室内操场木地板", (55, 11, 7.62), (18.5, 11.2, 0.08), MATS["wood"] if "wood" in MATS else MATS["stone"], 0.03)
    cube("室内篮球场中线", (55, 11, 7.69), (0.12, 10.2, 0.03), MATS["parking"], 0.004)
    cyl("室内篮球场中圈", (55, 11, 7.72), 1.25, 0.035, MATS["parking"], vertices=48)
    for y in [6.1, 15.9]:
        cyl(f"室内篮球架_{y}", (55, y, 8.45), 0.06, 2.6, MATS["metal"], vertices=12, rot=(math.radians(90), 0, 0))
        cube(f"室内篮球板_{y}", (55, y, 9.15), (1.6, 0.08, 0.9), MATS["glass"], 0.02)
    cube("设施索引_室内操场内部", (55, 11, 8.2), (1.0, 1.0, 0.35), MATS["orange"], 0.03)

    # Underground utility gallery with service manholes.
    cube("地下综合管廊_主廊", (-18, -11.5, -0.22), (82, 1.0, 0.28), MATS["metal"], 0.04)
    cube("地下综合管廊_支廊_教学区", (-8, 7, -0.22), (1.0, 38, 0.28), MATS["metal"], 0.04)
    cube("地下综合管廊_支廊_生活区", (35, 22, -0.22), (1.0, 34, 0.28), MATS["metal"], 0.04)
    for i, (x, y) in enumerate([(-57, -11.5), (-36, -11.5), (0, -11.5), (35, -11.5), (35, 22), (-8, 7)]):
        cyl(f"综合管廊检修井_{i}", (x, y, 0.05), 0.55, 0.12, MATS["metal"], vertices=28)
    cube("设施索引_地下综合管廊", (-18, -11.5, 0.38), (1.0, 1.0, 0.55), MATS["orange"], 0.04)

    # Assembly areas.
    for i, (x, y, label) in enumerate([(-18, -36, "南侧疏散集结点"), (8, 22, "中心疏散集结点"), (55, -43, "操场疏散集结点")]):
        cube(f"{label}_地面标识", (x, y, 0.16), (7.5, 4.5, 0.06), MATS["red"], 0.04)
        text(f"{label}_文字", label, (x, y, 0.28), 0.42, MATS["white"])


def make_daily_school_services():
    # Campus boundary and emergency circulation.
    cube("校园围墙_北侧", (0, 55.2, 1.0), (150, 0.45, 2.0), MATS["brick"], 0.04)
    cube("校园围墙_西侧", (-75.2, 0, 1.0), (0.45, 110, 2.0), MATS["brick"], 0.04)
    cube("校园围墙_东侧", (75.2, 0, 1.0), (0.45, 110, 2.0), MATS["brick"], 0.04)
    cube("校园围墙_南侧分段左", (-48, -55.2, 1.0), (54, 0.45, 2.0), MATS["brick"], 0.04)
    cube("校园围墙_南侧分段右", (48, -55.2, 1.0), (54, 0.45, 2.0), MATS["brick"], 0.04)
    cube("消防车道_西环", (-68, 0, 0.11), (4.2, 96, 0.08), MATS["road"], 0.04)
    cube("消防车道_东环", (68, 0, 0.11), (4.2, 96, 0.08), MATS["road"], 0.04)
    cube("消防车道_北环", (0, 43, 0.11), (132, 4.2, 0.08), MATS["road"], 0.04)
    cube("消防车道_南环", (0, -47, 0.11), (132, 4.2, 0.08), MATS["road"], 0.04)
    text("fire lane label", "环形消防车道 / 可达各组团", (-50, -45.1, 0.22), 0.55, MATS["white"])

    # Loading, maintenance, waste sorting, and delivery.
    cube("后勤装卸区_硬化地面", (67, 34, 0.12), (11, 7, 0.08), MATS["road"], 0.04)
    cube("后勤装卸月台", (64.2, 34, 0.6), (4.4, 5.8, 1.0), MATS["stone"], 0.04)
    cube("后勤货车", (70, 34, 0.85), (5.0, 1.7, 1.45), MATS["white"], 0.08)
    cube("垃圾分类站", (66, 42, 0.95), (8, 3.2, 1.8), MATS["metal"], 0.06)
    for i, (x, color, name) in enumerate([(63.6, MATS["blue"], "可回收"), (65.2, MATS["green"], "厨余"), (66.8, MATS["red"], "有害"), (68.4, MATS["yellow"], "其他")]):
        cube(f"垃圾分类桶_{name}", (x, 41.5, 0.72), (0.9, 0.8, 1.1), color, 0.04)
    cube("设施索引_后勤装卸区", (67, 34, 0.55), (1.0, 1.0, 0.62), MATS["orange"], 0.04)
    cube("设施索引_垃圾分类站", (66, 42, 0.55), (1.0, 1.0, 0.62), MATS["orange"], 0.04)

    # General specialist classrooms beyond STEM.
    specialty_rooms = [
        ("语言实验室", 18, -29.3, MATS["blue"]),
        ("美术教室", 22, -29.3, MATS["orange"]),
        ("音乐教室", 26, -29.3, MATS["purple"]),
        ("校史馆", -5.5, -25.8, MATS["stone"]),
        ("教师发展中心", 5.5, -25.8, MATS["green"]),
        ("家长接待室", -5.5, -17.3, MATS["white"]),
    ]
    for name, x, y, color in specialty_rooms:
        cube(f"设施索引_{name}", (x, y, 0.42), (0.95, 0.95, 0.58), MATS["orange"], 0.04)
        cube(f"{name}_开放剖面空间", (x, y, 1.12), (3.2, 2.2, 1.65), MATS["glass"], 0.04)
        cube(f"{name}_功能墙", (x, y + 1.08, 1.25), (2.4, 0.12, 0.8), color, 0.02)
        text(f"{name}_标签", name, (x, y, 2.05), 0.34, MATS["white"])

    # Toilets, elevators, access control, and stairs as repeatable floor service nodes.
    for i, (x, y) in enumerate([(-44, 8), (-18, 16), (8, 16), (34, 8), (-44, 0), (-18, 8), (8, 8), (34, 0)]):
        cube(f"卫生间节点_{i}", (x, y, 5.62), (1.2, 0.85, 0.25), MATS["white"], 0.03)
        cube(f"电梯节点_{i}", (x + 1.55, y, 5.65), (0.75, 0.75, 0.42), MATS["metal"], 0.03)
        cube(f"楼梯节点_{i}", (x - 1.55, y, 5.65), (0.9, 0.9, 0.38), MATS["stone"], 0.03)
        cube(f"门禁闸机节点_{i}", (x, y - 0.85, 5.58), (1.4, 0.18, 0.42), MATS["screen"], 0.02)
    cube("设施索引_卫生间电梯楼梯门禁", (-18, 18.5, 5.95), (1.0, 1.0, 0.45), MATS["orange"], 0.04)

    # Clinic and counseling detail.
    for i, (x, y, name, color) in enumerate([(9.0, 30.5, "校医诊室", MATS["white"]), (12.0, 30.5, "隔离观察室", MATS["yellow"]), (15.0, 30.5, "心理咨询室", MATS["purple"])]):
        cube(f"设施索引_{name}", (x, y, 0.42), (0.95, 0.95, 0.58), MATS["orange"], 0.04)
        cube(f"{name}_房间", (x, y, 3.95), (2.4, 1.8, 0.16), color, 0.03)
        cube(f"{name}_桌床设备", (x, y, 4.18), (1.2, 0.55, 0.18), MATS["metal"], 0.02)

    # Small weather/air quality science station.
    cyl("校园气象站_立杆", (-61, 38, 2.0), 0.07, 4.0, MATS["metal"], vertices=12)
    cyl("校园气象站_风速仪", (-61, 38, 4.2), 0.28, 0.08, MATS["white"], vertices=24)
    cube("校园空气质量传感器", (-60.4, 38, 3.1), (0.45, 0.32, 0.55), MATS["screen"], 0.04)
    cube("设施索引_校园气象站空气质量", (-61, 38, 0.55), (1.0, 1.0, 0.62), MATS["orange"], 0.04)


def make_public_amenities_and_special_interiors():
    # Library/admin internal reading and resource zones.
    cube("图书馆内部_开放阅览区", (0, -21, 5.55), (11.5, 5.6, 0.16), MATS["white"], 0.03)
    for i, x in enumerate([-4.5, -2.7, -0.9, 0.9, 2.7, 4.5]):
        cube(f"图书馆书架_{i}", (x, -22.6, 5.9), (0.36, 2.4, 0.85), MATS["wood"] if "wood" in MATS else MATS["stone"], 0.03)
    for row in range(2):
        for col in range(4):
            cube(f"阅览区桌椅_{row}_{col}", (-3.6 + col * 2.4, -18.9 + row * 1.25, 5.88), (1.2, 0.55, 0.12), MATS["paving"], 0.02)
    cube("图书馆自助借还机", (5.4, -18.2, 5.95), (0.55, 0.45, 0.75), MATS["screen"], 0.04)
    cube("设施索引_图书馆内部阅览区", (0, -21, 6.18), (1.0, 1.0, 0.38), MATS["orange"], 0.03)

    # Sports support spaces.
    for i, (x, y, name, color) in enumerate([(47, 18.4, "体育更衣室", MATS["blue"]), (51, 18.4, "淋浴间", MATS["white"]), (59, 18.4, "体育器材室", MATS["orange"]), (63, 18.4, "裁判医务点", MATS["green"])]):
        cube(f"设施索引_{name}", (x, y, 7.95), (0.95, 0.95, 0.36), MATS["orange"], 0.03)
        cube(f"{name}_剖面房间", (x, y, 7.68), (3.2, 2.0, 0.14), color, 0.03)
        cube(f"{name}_柜台设备", (x, y + 0.52, 7.9), (1.8, 0.28, 0.26), MATS["metal"], 0.02)
    for i, x in enumerate([57.4, 58.2, 59.0, 59.8, 60.6]):
        cyl(f"体育器材室_球架篮球_{i}", (x, 17.6, 8.1), 0.18, 0.18, MATS["orange"], vertices=18)

    # Daily public service nodes across campus.
    public_nodes = [
        ("校园导视屏_入口", -4, -50, MATS["screen"]),
        ("校园导视屏_中心", 2, -5, MATS["screen"]),
        ("校园导视屏_生活区", 34, 27, MATS["screen"]),
        ("AED急救箱_入口", -11, -51, MATS["red"]),
        ("AED急救箱_操场", 22, -31, MATS["red"]),
        ("AED急救箱_体育馆", 43, 13, MATS["red"]),
        ("应急电话_西区", -53, 8, MATS["yellow"]),
        ("应急电话_东区", 52, 3, MATS["yellow"]),
        ("饮水点_教学区", -10, 3, MATS["blue"]),
        ("饮水点_操场", 25, -38, MATS["blue"]),
        ("储物柜_教学区", -16, 9, MATS["metal"]),
        ("储物柜_体育馆", 48, 7, MATS["metal"]),
        ("电子班牌_初中楼", -38, 10.4, MATS["screen"]),
        ("电子班牌_高中楼", -12, 18.4, MATS["screen"]),
        ("电子班牌_国际部", 14, 18.4, MATS["screen"]),
        ("访客服务终端", -13, -50.8, MATS["screen"]),
        ("充电服务站_自行车棚", 37, -51.8, MATS["green"]),
    ]
    for name, x, y, material in public_nodes:
        cube(name, (x, y, 1.0), (0.72, 0.35, 1.45), material, 0.04)
        cube(f"设施索引_{name}", (x, y, 0.32), (0.8, 0.8, 0.42), MATS["orange"], 0.03)


def make_planning_admin_and_learning_landscape():
    # Readable district overlays make the map behave like a planning model, not only a collection of buildings.
    districts = [
        ("分区边界_入口共享区", 0, -39, 52, 23, MATS["orange"], "入口共享区"),
        ("分区边界_教学静区", -6, 6, 96, 34, MATS["blue"], "院落教学静区"),
        ("分区边界_运动活力区", 47, -29, 51, 30, MATS["red"], "运动活力区"),
        ("分区边界_生活后勤区", 42, 34, 62, 22, MATS["green"], "生活后勤区"),
        ("分区边界_科技运维区", -49, -15, 34, 33, MATS["purple"], "科技运维区"),
    ]
    for name, x, y, w, d, material, label in districts:
        cube(name, (x, y, 0.135), (w, d, 0.035), material, 0.03)
        text(f"{name}_文字", label, (x, y + d / 2 - 1.6, 0.28), 0.46, MATS["white"])

    # Additional controlled entries, parking, and service circulation.
    cube("西侧后勤车行门岗", (-75.2, 34, 1.2), (0.7, 5.5, 2.4), MATS["brick"], 0.05)
    cube("西侧后勤车行闸机", (-71.8, 34, 0.55), (5.8, 0.35, 1.1), MATS["metal"], 0.03)
    cube("东侧运动场应急门", (75.2, -33, 1.2), (0.7, 6.2, 2.4), MATS["brick"], 0.05)
    cube("东侧应急车行闸机", (71.5, -33, 0.55), (6.2, 0.35, 1.1), MATS["red"], 0.03)
    cube("访客停车场", (-47, -50.5, 0.13), (20, 5.4, 0.08), MATS["road"], 0.03)
    cube("教职工停车场", (-56, 43.5, 0.13), (21, 6.0, 0.08), MATS["road"], 0.03)
    for i, x in enumerate([-54, -50, -46, -42, -38]):
        cube(f"访客停车位_{i}", (x, -50.5, 0.19), (0.12, 4.8, 0.025), MATS["parking"], 0.004)
    for i, x in enumerate([-64, -60, -56, -52, -48]):
        cube(f"教职工停车位_{i}", (x, 43.5, 0.19), (0.12, 5.3, 0.025), MATS["parking"], 0.004)
    cube("设施索引_多门岗停车系统", (-67, 40, 0.48), (1.0, 1.0, 0.55), MATS["orange"], 0.04)

    # Administration cutaway inside the library/administration center.
    admin_rooms = [
        ("校长室", -5.0, -23.6, MATS["wood"]),
        ("行政办公室", -2.5, -23.6, MATS["white"]),
        ("教务处", 0.0, -23.6, MATS["blue"]),
        ("总务处", 2.5, -23.6, MATS["green"]),
        ("财务室", 5.0, -23.6, MATS["yellow"]),
        ("会议室", -3.2, -18.0, MATS["stone"]),
        ("档案室", 3.2, -18.0, MATS["metal"]),
    ]
    for name, x, y, material in admin_rooms:
        cube(f"行政剖面_{name}", (x, y, 6.38), (2.1, 1.55, 0.13), material, 0.025)
        cube(f"行政剖面_{name}_桌柜", (x, y, 6.55), (1.15, 0.38, 0.18), MATS["wood"], 0.015)
        text(f"行政剖面_{name}_标签", name, (x, y, 6.8), 0.24, MATS["white"])
    cube("设施索引_行政办公剖面", (0, -21, 7.05), (1.0, 1.0, 0.35), MATS["orange"], 0.03)

    # Science safety equipment around chemistry and biology labs.
    lab_safety_nodes = [
        ("化学品暂存柜", -22.0, -31.3, MATS["yellow"]),
        ("危废暂存箱", -24.2, -31.3, MATS["red"]),
        ("通风橱", -23.0, -27.9, MATS["metal"]),
        ("紧急冲淋洗眼器", -20.8, -29.4, MATS["green"]),
        ("生物安全柜", -18.2, -31.3, MATS["screen"]),
    ]
    for name, x, y, material in lab_safety_nodes:
        cube(name, (x, y, 1.38), (0.62, 0.42, 1.15), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.42), (0.75, 0.75, 0.46), MATS["orange"], 0.03)

    # Campus water, HVAC, and fire infrastructure as dedicated service rooms.
    utility_nodes = [
        ("空调能源站", -59, 35.5, MATS["white"]),
        ("冷水机组", -63, 35.5, MATS["metal"]),
        ("循环水泵", -55, 35.5, MATS["blue"]),
        ("消防水池", -69, 36, MATS["water"]),
        ("消防泵房", -69, 31, MATS["red"]),
        ("生活水泵房", -54, 31, MATS["green"]),
        ("弱电间IDF节点", -48, 2, MATS["screen"]),
        ("弱电间IDF节点_生活区", 43, 29, MATS["screen"]),
    ]
    for name, x, y, material in utility_nodes:
        cube(name, (x, y, 1.0), (2.6, 1.8, 1.75), material, 0.05)
        cube(f"设施索引_{name}", (x, y, 0.36), (0.78, 0.78, 0.44), MATS["orange"], 0.03)
    cube("楼宇自控BAS控制柜", (-36, -4.0, 1.45), (1.0, 0.75, 1.7), MATS["screen"], 0.04)
    cube("一键日夜模式控制屏", (-36, -3.0, 1.35), (0.85, 0.18, 0.55), MATS["screen"], 0.02)
    cube("室外照明回路控制箱", (-35, -3.0, 0.92), (0.72, 0.38, 1.1), MATS["yellow"], 0.03)

    # Athletics completeness: spectator, official, and field-event elements.
    cube("操场看台_主体", (45, -47.3, 1.0), (34, 3.4, 1.8), MATS["stone"], 0.08)
    for i in range(4):
        cube(f"操场看台_座席层_{i}", (45, -48.2 + i * 0.55, 1.45 + i * 0.18), (32, 0.25, 0.15), MATS["wood"], 0.02)
    cube("操场主席台", (45, -51.2, 1.4), (12, 2.0, 2.2), MATS["brick"], 0.08)
    cube("操场电子记分屏", (63.5, -28, 3.0), (0.18, 5.4, 2.4), MATS["screen"], 0.03)
    cube("跳远沙坑", (20, -24, 0.15), (8.5, 2.6, 0.12), MATS["paving"], 0.04)
    cube("铅球投掷区", (28, -21, 0.15), (4.0, 4.0, 0.1), MATS["paving"], 0.08)
    cube("设施索引_操场看台主席台记分屏", (45, -47.3, 2.4), (1.0, 1.0, 0.48), MATS["orange"], 0.04)

    # Outdoor learning landscapes.
    cyl("露天剧场_半圆台阶", (-25, 38, 0.18), 5.0, 0.12, MATS["stone"], vertices=48)
    cyl("露天剧场_中心舞台", (-25, 38, 0.38), 2.3, 0.2, MATS["wood"], vertices=48)
    cube("阅读花园_木平台", (-7, 37, 0.18), (10, 4.2, 0.14), MATS["wood"], 0.05)
    for i, x in enumerate([-10, -7, -4]):
        cube(f"阅读花园_长椅_{i}", (x, 37.4, 0.48), (1.9, 0.35, 0.28), MATS["wood"], 0.03)
    cube("生态课程湿地", (-39, 40.5, 0.13), (10, 3.2, 0.08), MATS["wetland"], 0.06)
    cube("劳动教育菜园", (8, 38, 0.14), (10, 4.0, 0.09), MATS["green"], 0.04)
    cube("校园温室", (19, 38, 1.05), (7.5, 3.2, 2.0), MATS["glass"], 0.06)
    cube("设施索引_室外学习景观", (-7, 39.8, 0.52), (1.0, 1.0, 0.5), MATS["orange"], 0.04)


def make_sports_and_living():
    # Outdoor athletics
    cube("outdoor playground base", (45, -28, 0.06), (44, 26, 0.08), MATS["track"], 0.3)
    cube("football field green center", (45, -28, 0.12), (31, 16, 0.08), MATS["field"], 0.1)
    for off in [-8.8, 8.8]:
        cube(f"track lane stripe {off}", (45, -28 + off, 0.18), (42, 0.12, 0.03), MATS["white"], 0.01)
    text("outdoor sports label", "400m操场 / 足球场", (45, -28, 0.25), 1.0, MATS["white"])
    for i, (x, y) in enumerate([(18, -42), (26, -42), (34, -42), (18, -35), (26, -35), (34, -35)]):
        cube(f"basketball court {i}", (x, y, 0.08), (6.5, 4.3, 0.06), MATS["paving"], 0.04)
        cyl(f"basketball hoop {i}", (x + 2.8, y, 1.6), 0.05, 3.0, MATS["metal"], vertices=12, rot=(math.radians(90), 0, 0))
    building("indoor sports hall", 55, 11, 24, 16, 7.0, "室内体育馆", floors=2, accent=MATS["orange"])
    cube("sports hall translucent roof", (55, 11, 7.35), (21, 13, 0.25), MATS["glass"], 0.08)
    building("canteen", 30, 31, 17, 9, 4.2, "食堂", floors=2, accent=MATS["yellow"])
    building("student dormitory", 54, 31, 27, 10, 5.8, "生活组团/宿舍", floors=4, accent=MATS["stone"])
    building("clinic and counseling", 12, 32, 12, 8, 3.7, "医务/心理中心", floors=2, accent=MATS["white"])


def make_service_and_safety():
    cube("standalone transformer yard fence", (-62, 28, 1.0), (15, 9, 2.0), MATS["metal"], 0.03)
    cube("transformer yard gravel pad", (-62, 28, 0.08), (14, 8, 0.08), MATS["paving"], 0.02)
    for i, x in enumerate([-66, -62, -58]):
        cube(f"outdoor transformer {i}", (x, 28, 1.0), (2.2, 1.5, 1.8), MATS["yellow"], 0.05)
    text("utility yard label", "室外变配电/应急电源区", (-62, 33.2, 0.2), 0.7, MATS["white"])
    cube("diesel generator shelter", (-47, 29, 1.0), (8, 5, 2.0), MATS["stone"], 0.08)
    cube("generator exhaust stack", (-43.5, 30.8, 2.5), (0.55, 0.55, 2.2), MATS["metal"], 0.04)
    for i, (x, y, r) in enumerate([(-60, -38, 0.2), (-30, 18, 0.1), (0, -20, -0.4), (30, 8, 1.3), (60, -43, 2.2), (58, 24, -2.5)]):
        add_security_camera(f"campus perimeter CCTV {i}", x, y, 3.0, rot_z=r)
    for i, x in enumerate(range(-54, 55, 18)):
        cyl(f"smart light pole {i}", (x, -15, 2.2), 0.08, 4.3, MATS["metal"], vertices=12)
        cube(f"smart light pole lamp {i}", (x, -14.5, 4.35), (1.0, 0.18, 0.18), MATS["light"], 0.04)


def make_map_index_and_system_layers():
    # Survey-style map aids: coordinates, north arrow, scale bar, building IDs, and layer controls.
    for i, x in enumerate(range(-70, 71, 10)):
        cube(f"坐标网格_X{i}", (x, 0, 0.155), (0.045, 108, 0.025), MATS["white"], 0.002)
        text(f"坐标网格_X{i}_标注", f"X{x:+03d}", (x, -53.2, 0.28), 0.28, MATS["white"])
    for i, y in enumerate(range(-50, 51, 10)):
        cube(f"坐标网格_Y{i}", (0, y, 0.16), (148, 0.045, 0.025), MATS["white"], 0.002)
        text(f"坐标网格_Y{i}_标注", f"Y{y:+03d}", (-72.2, y, 0.28), 0.28, MATS["white"])
    cube("指北针_底座", (68, 49, 0.22), (4.5, 4.5, 0.08), MATS["panel"], 0.05)
    cyl("指北针_北向箭头", (68, 49.6, 0.42), 0.62, 0.12, MATS["red"], vertices=3, rot=(0, 0, 0))
    text("指北针_N", "N", (68, 51.5, 0.52), 0.7, MATS["white"])
    cube("比例尺_50m", (55, 49.2, 0.24), (8.0, 0.24, 0.08), MATS["white"], 0.01)
    cube("比例尺_25m分段", (53, 49.2, 0.3), (4.0, 0.28, 0.1), MATS["panel"], 0.01)
    text("比例尺_文字", "比例尺 0-50m", (55, 50.0, 0.34), 0.35, MATS["white"])

    building_ids = [
        ("建筑编号_B01_图书行政", 0, -21, "B01 图书行政"),
        ("建筑编号_B02_STEM", -23, -24, "B02 STEM"),
        ("建筑编号_B03_博雅中心", 23, -24, "B03 博雅"),
        ("建筑编号_T01_初中楼", -38, 4, "T01 初中"),
        ("建筑编号_T02_高中楼", -12, 12, "T02 高中"),
        ("建筑编号_T03_国际部", 14, 12, "T03 国际"),
        ("建筑编号_T04_共享教室", 40, 4, "T04 共享"),
        ("建筑编号_O01_科技运维", -48, -21, "O01 运维"),
        ("建筑编号_S01_体育馆", 55, 11, "S01 体育"),
        ("建筑编号_L01_食堂", 30, 31, "L01 食堂"),
        ("建筑编号_L02_宿舍", 54, 31, "L02 宿舍"),
        ("建筑编号_M01_医务心理", 12, 32, "M01 医务"),
    ]
    for name, x, y, label in building_ids:
        cube(name, (x - 4.2, y + 4.2, 4.95), (2.6, 0.18, 0.55), MATS["panel"], 0.025)
        text(f"{name}_文字", label, (x - 4.2, y + 4.08, 5.0), 0.25, MATS["light"], rot=(math.radians(90), 0, 0))

    floor_cards = [
        ("楼层功能牌_教学楼", -24, 20, "1F公共/2F普通教室/3F实验与选修"),
        ("楼层功能牌_科技楼", -60, -2, "微机室/服务器/配电/监控"),
        ("楼层功能牌_生活组团", 46, 43, "食堂/宿舍/洗衣/医务心理"),
        ("楼层功能牌_体育区", 60, -42, "室外操场/体育馆/更衣淋浴"),
    ]
    for name, x, y, body in floor_cards:
        cube(name, (x, y, 1.2), (7.5, 0.28, 1.6), MATS["panel"], 0.05)
        text(f"{name}_文字", body, (x, y - 0.18, 1.35), 0.23, MATS["white"], rot=(math.radians(90), 0, 0))

    layer_panel_items = [
        ("电子沙盘图层_建筑", MATS["brick"]),
        ("电子沙盘图层_消防疏散", MATS["red"]),
        ("电子沙盘图层_安防覆盖", MATS["screen"]),
        ("电子沙盘图层_网络拓扑", MATS["blue"]),
        ("电子沙盘图层_能源水务", MATS["yellow"]),
        ("电子沙盘图层_日夜应急", MATS["light"]),
    ]
    cube("电子沙盘图层控制台", (-65, 51.4, 1.15), (18, 0.5, 2.4), MATS["panel"], 0.06)
    for i, (name, material) in enumerate(layer_panel_items):
        z = 2.05 - i * 0.32
        cube(name, (-71.0, 51.08, z), (0.42, 0.1, 0.18), material, 0.02)
        text(f"{name}_文字", name.replace("电子沙盘图层_", ""), (-65.5, 51.02, z), 0.22, MATS["white"], rot=(math.radians(90), 0, 0))

    route_specs = [
        ("访客动线", -8, -51, 0, -21, MATS["orange"]),
        ("学生动线", 0, -47, -12, 12, MATS["blue"]),
        ("后勤动线", -68, 34, 67, 34, MATS["green"]),
        ("无障碍连续动线", 9, -50, 13, 32, MATS["white"]),
        ("消防登高面", 45, -43, 55, 18, MATS["red"]),
    ]
    for name, x1, y1, x2, y2, material in route_specs:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(f"{name}_路线", ((x1 + x2) / 2, (y1 + y2) / 2, 0.34), (length, 0.18, 0.05), material, 0.01, rot_z=angle)
        cyl(f"{name}_箭头", (x2, y2, 0.39), 0.38, 0.08, material, vertices=3, rot=(0, 0, angle - math.pi / 2))

    system_boards = [
        ("消防疏散总图", -67, -42, MATS["red"]),
        ("安防覆盖总图", -67, -37, MATS["screen"]),
        ("网络拓扑总图", -67, -32, MATS["blue"]),
        ("能耗水务总图", -67, -27, MATS["yellow"]),
    ]
    for name, x, y, material in system_boards:
        cube(name, (x, y, 1.15), (6.4, 0.34, 1.45), MATS["panel"], 0.05)
        cube(f"{name}_彩色标题", (x - 2.25, y - 0.22, 1.55), (1.0, 0.08, 0.3), material, 0.01)
        text(f"{name}_文字", name, (x, y - 0.25, 1.12), 0.34, MATS["white"], rot=(math.radians(90), 0, 0))

    for i, (x, y) in enumerate([(-60, -38), (-30, 18), (0, -20), (30, 8), (60, -43), (58, 24), (-5, -52), (5, -52)]):
        cyl(f"CCTV覆盖扇区_{i}", (x, y, 0.21), 2.2, 0.035, MATS["glass"], vertices=32)
    cube("设施索引_地图索引图层控制", (-65, 51.4, 2.62), (1.0, 1.0, 0.4), MATS["orange"], 0.04)


def make_teaching_detail_and_capacity_schedule():
    # Teaching blocks become legible as a room schedule: grade zones, room numbers, teacher offices, and capacity.
    teaching_blocks = [
        ("初中部", -38, 4, "T01"),
        ("高中部", -12, 12, "T02"),
        ("国际部", 14, 12, "T03"),
        ("共享教室", 40, 4, "T04"),
    ]
    for block_idx, (grade, cx, cy, code) in enumerate(teaching_blocks):
        cube(f"年级分区牌_{grade}", (cx, cy - 6.6, 1.25), (6.8, 0.28, 1.45), MATS["panel"], 0.045)
        text(f"年级分区牌_{grade}_文字", f"{code} {grade}", (cx, cy - 6.78, 1.42), 0.38, MATS["light"], rot=(math.radians(90), 0, 0))
        for floor in range(1, 4):
            for room in range(1, 5):
                x = cx - 6.0 + (room - 1) * 4.0
                y = cy + 4.1 + (floor - 1) * 0.52
                z = 5.86 + (floor - 1) * 0.08
                room_code = f"{code}-{floor}{room:02d}"
                cube(f"教室编号_{room_code}", (x, y, z), (2.4, 0.16, 0.38), MATS["screen"], 0.018)
                text(f"教室编号_{room_code}_文字", room_code, (x, y - 0.1, z + 0.02), 0.18, MATS["light"], rot=(math.radians(90), 0, 0))
        support_rooms = [
            ("班主任办公室", cx - 6.0, cy - 4.5, MATS["wood"]),
            ("备课室", cx - 2.0, cy - 4.5, MATS["white"]),
            ("年级组办公室", cx + 2.0, cy - 4.5, MATS["green"]),
            ("学生储物间", cx + 6.0, cy - 4.5, MATS["metal"]),
        ]
        for name, x, y, material in support_rooms:
            cube(f"{grade}_{name}", (x, y, 5.72), (2.4, 1.15, 0.16), material, 0.025)
            cube(f"{grade}_{name}_家具", (x, y, 5.95), (1.1, 0.42, 0.18), MATS["wood"], 0.015)
        cube(f"{grade}_课间灰空间", (cx, cy - 1.15, 5.68), (13.8, 1.1, 0.12), MATS["paving"], 0.025)

    # Covered links between learning courtyards: useful for a complete walkable campus map.
    link_specs = [
        ("风雨连廊_初高中", -25, 8, 22, 1.6, 0),
        ("风雨连廊_高中国际", 1, 12, 22, 1.6, 0),
        ("风雨连廊_国际共享", 27, 8, 22, 1.6, 0),
        ("风雨连廊_教学到图书馆", -6, -6, 34, 1.35, math.radians(-28)),
    ]
    for name, x, y, length, width, rot_z in link_specs:
        cube(name, (x, y, 2.75), (length, width, 0.22), MATS["glass"], 0.04, rot_z=rot_z)
        for off in [-length / 2 + 2.0, length / 2 - 2.0]:
            dx = math.cos(rot_z) * off
            dy = math.sin(rot_z) * off
            cyl(f"{name}_支柱_{off:.1f}", (x + dx, y + dy, 1.35), 0.08, 2.5, MATS["metal"], vertices=12)

    # Representative 55-seat smart classroom cutaway embedded in the shared teaching block.
    base_x, base_y, base_z = 40, 12.2, 6.2
    cube("55人智慧大教室样板_地面", (base_x, base_y, base_z), (14.0, 8.2, 0.14), MATS["white"], 0.03)
    cube("55人智慧大教室样板_漂亮地台", (base_x, base_y + 3.45, base_z + 0.18), (13.4, 1.45, 0.28), MATS["wood"], 0.04)
    cube("55人智慧大教室样板_中间黑板", (base_x, base_y + 4.25, base_z + 0.88), (4.2, 0.12, 1.0), MATS["panel"], 0.02)
    cube("55人智慧大教室样板_左触控屏", (base_x - 4.1, base_y + 4.25, base_z + 0.88), (2.2, 0.12, 1.0), MATS["screen"], 0.02)
    cube("55人智慧大教室样板_右触控屏", (base_x + 4.1, base_y + 4.25, base_z + 0.88), (2.2, 0.12, 1.0), MATS["screen"], 0.02)
    cube("55人智慧大教室样板_嵌入式讲台电脑", (base_x, base_y + 2.65, base_z + 0.58), (2.3, 0.82, 0.56), MATS["wood"], 0.03)
    cube("55人智慧大教室样板_屏幕右侧IO排线仓", (base_x + 5.5, base_y + 4.18, base_z + 0.78), (0.62, 0.18, 0.82), MATS["metal"], 0.02)
    for i, label in enumerate(["USB", "DP", "HDMI", "LAN"]):
        cube(f"55人智慧大教室样板_IO_{label}", (base_x + 5.5, base_y + 4.0, base_z + 1.08 - i * 0.18), (0.34, 0.04, 0.08), MATS["blue"] if i % 2 == 0 else MATS["yellow"], 0.006)
    cube("55人智慧大教室样板_墙内线槽", (base_x + 5.5, base_y + 2.1, base_z + 0.34), (0.2, 4.2, 0.12), MATS["yellow"], 0.01)
    cube("55人智慧大教室样板_地面线槽", (base_x + 2.8, base_y + 2.0, base_z + 0.26), (5.6, 0.18, 0.08), MATS["yellow"], 0.01)
    cube("55人智慧大教室样板_后排黑板报", (base_x, base_y - 4.25, base_z + 0.82), (10.8, 0.1, 0.9), MATS["green"], 0.02)
    for i, x in enumerate([-4.8, -2.4, 0, 2.4, 4.8]):
        cube(f"55人智慧大教室样板_黑板报栏目_{i}", (base_x + x, base_y - 4.32, base_z + 0.84), (1.6, 0.05, 0.56), MATS["orange"] if i % 2 else MATS["blue"], 0.01)
    for i, x in enumerate([-5.4, -1.8, 1.8, 5.4]):
        cube(f"55人智慧大教室样板_LED灯带_{i}", (base_x + x, base_y, base_z + 1.95), (2.5, 0.18, 0.08), MATS["light"], 0.02)
        cyl(f"55人智慧大教室样板_吊扇_{i}", (base_x + x, base_y - 0.9, base_z + 1.74), 0.55, 0.055, MATS["metal"], vertices=24)
    for i, x in enumerate([-6.5, 6.5]):
        cube(f"55人智慧大教室样板_壁挂空调_{i}", (base_x + x, base_y + 0.9, base_z + 1.55), (0.18, 1.8, 0.45), MATS["white"], 0.035)
        cube(f"55人智慧大教室样板_空调外机连线_{i}", (base_x + x, base_y + 2.2, base_z + 1.5), (0.12, 1.8, 0.08), MATS["metal"], 0.008)

    seat_index = 0
    group_centers = [(-4.7, -1.8), (-1.55, -1.8), (1.55, -1.8), (4.7, -1.8)]
    for group, (gx, gy) in enumerate(group_centers):
        for row in range(4):
            for pair in range(2):
                desk_x = base_x + gx + (pair - 0.5) * 1.15
                desk_y = base_y + gy + row * 0.88
                cube(f"55人智慧大教室样板_四组双人桌_{group}_{row}_{pair}", (desk_x, desk_y, base_z + 0.42), (0.86, 0.5, 0.12), MATS["wood"], 0.018)
                cube(f"55人智慧大教室样板_抽屉书本_{group}_{row}_{pair}", (desk_x, desk_y - 0.08, base_z + 0.31), (0.62, 0.18, 0.08), MATS["blue"], 0.006)
                for side in [-0.18, 0.18]:
                    if seat_index < 55:
                        cube(f"55人智慧大教室样板_学生座位_{seat_index:02d}", (desk_x + side, desk_y - 0.38, base_z + 0.38), (0.26, 0.22, 0.18), MATS["stone"], 0.012)
                        seat_index += 1
    while seat_index < 55:
        cube(f"55人智慧大教室样板_学生座位_{seat_index:02d}", (base_x + 5.9, base_y - 3.1 + (seat_index - 32) * 0.16, base_z + 0.38), (0.26, 0.22, 0.18), MATS["stone"], 0.012)
        seat_index += 1
    cube("设施索引_55人智慧大教室样板", (base_x, base_y, base_z + 2.25), (1.0, 1.0, 0.38), MATS["orange"], 0.03)

    # Capacity and class schedule board next to the teaching zone.
    cube("容量统计总表", (-4, 28.8, 1.5), (26, 0.42, 2.35), MATS["panel"], 0.06)
    text("容量统计总表_标题", "教学容量：普通教室48间 / 55人大教室样板 / 走班与选修空间", (-4, 28.55, 2.15), 0.34, MATS["light"], rot=(math.radians(90), 0, 0))
    text("容量统计总表_正文", "初中·高中·国际·共享四组团，连廊连接图书馆/STEM/运动区", (-4, 28.52, 1.35), 0.28, MATS["white"], rot=(math.radians(90), 0, 0))


def make_living_logistics_detail():
    # Canteen operations: receiving, storage, cooking, serving, dish return, and food-safety monitoring.
    canteen_nodes = [
        ("食堂后厨_收货验收区", 23.2, 36.4, MATS["paving"]),
        ("食堂后厨_冷库", 25.8, 36.4, MATS["blue"]),
        ("食堂后厨_干货库", 28.4, 36.4, MATS["wood"]),
        ("食堂后厨_粗加工间", 31.0, 36.4, MATS["metal"]),
        ("食堂后厨_烹饪区", 33.6, 36.4, MATS["yellow"]),
        ("食堂后厨_备餐间", 36.2, 36.4, MATS["white"]),
        ("食堂后厨_洗消间", 38.8, 36.4, MATS["green"]),
        ("食堂后厨_留样柜", 39.0, 32.5, MATS["screen"]),
        ("食堂食品安全监测屏", 22.4, 31.2, MATS["screen"]),
    ]
    for name, x, y, material in canteen_nodes:
        cube(name, (x, y, 4.95), (2.0, 1.25, 0.22), material, 0.025)
        cube(f"设施索引_{name}", (x, y, 5.25), (0.58, 0.58, 0.28), MATS["orange"], 0.02)
    for i, x in enumerate([23.2, 25.8, 28.4, 31.0, 33.6, 36.2, 38.8]):
        cube(f"食堂洁污分流动线_{i}", (x, 34.7, 4.78), (1.7, 0.12, 0.06), MATS["green"] if i < 4 else MATS["red"], 0.006)
    for i, x in enumerate([24.0, 27.0, 30.0, 33.0, 36.0]):
        cube(f"食堂取餐排队栏杆_{i}", (x, 27.8, 4.75), (0.08, 2.4, 0.38), MATS["metal"], 0.01)
        cube(f"食堂餐盘回收口_{i}", (x, 25.9, 4.85), (1.0, 0.18, 0.5), MATS["screen"], 0.01)

    # Dormitory detail: sample rooms, bathrooms, laundry, study, houseparent, and night management.
    dorm_modules = [
        ("宿舍样板间_四人间A", 44, 33.8, MATS["white"]),
        ("宿舍样板间_四人间B", 47.6, 33.8, MATS["white"]),
        ("宿舍样板间_四人间C", 51.2, 33.8, MATS["white"]),
        ("宿舍样板间_四人间D", 54.8, 33.8, MATS["white"]),
        ("宿舍公共卫生间", 58.8, 33.8, MATS["blue"]),
        ("宿舍淋浴间", 62.8, 33.8, MATS["green"]),
        ("宿舍洗衣烘干房", 66.0, 31.8, MATS["metal"]),
        ("宿舍夜间值班室", 41.8, 31.8, MATS["wood"]),
        ("宿舍公共自习室", 50.2, 31.8, MATS["paving"]),
        ("宿舍生活导师室", 57.0, 31.8, MATS["wood"]),
    ]
    for name, x, y, material in dorm_modules:
        cube(name, (x, y, 6.88), (3.0, 1.65, 0.18), material, 0.026)
        cube(f"设施索引_{name}", (x, y, 7.16), (0.55, 0.55, 0.28), MATS["orange"], 0.02)
    for room, x in enumerate([44, 47.6, 51.2, 54.8]):
        for bed in range(4):
            bx = x - 0.85 + (bed % 2) * 1.7
            by = 33.45 + (bed // 2) * 0.68
            cube(f"宿舍样板间_床铺_{room}_{bed}", (bx, by, 7.1), (0.65, 0.48, 0.16), MATS["blue"] if bed % 2 else MATS["green"], 0.015)
        cube(f"宿舍样板间_书桌柜_{room}", (x, 34.4, 7.12), (1.8, 0.22, 0.22), MATS["wood"], 0.012)
    for i, x in enumerate([58.2, 59.4, 62.2, 63.4]):
        cyl(f"宿舍卫浴洁具_{i}", (x, 33.45, 7.08), 0.18, 0.16, MATS["white"], vertices=18)
    for i, x in enumerate([65.3, 66.0, 66.7]):
        cyl(f"宿舍洗衣烘干机_{i}", (x, 31.45, 7.08), 0.24, 0.32, MATS["white"], vertices=24)
    for i, x in enumerate([48.8, 50.2, 51.6]):
        cube(f"宿舍自习桌_{i}", (x, 31.45, 7.08), (1.0, 0.38, 0.14), MATS["wood"], 0.012)
        cube(f"宿舍自习灯_{i}", (x, 31.45, 7.34), (0.55, 0.08, 0.08), MATS["light"], 0.006)

    # Logistics support and inventory tracking around the service yard.
    logistics_nodes = [
        ("后勤仓储间", 62, 38, MATS["metal"]),
        ("清洁工具间", 65, 38, MATS["green"]),
        ("维修工坊", 68, 38, MATS["yellow"]),
        ("校服教材周转库", 71, 38, MATS["blue"]),
        ("后勤数字库存屏", 66.5, 30.5, MATS["screen"]),
        ("冷链卸货位", 72, 31, MATS["blue"]),
        ("厨余暂存冷藏箱", 69.5, 43.5, MATS["green"]),
        ("油烟净化设备", 39.5, 38.4, MATS["metal"]),
    ]
    for name, x, y, material in logistics_nodes:
        cube(name, (x, y, 1.35), (2.2, 1.25, 1.35), material, 0.04)
        cube(f"设施索引_{name}", (x, y, 0.42), (0.7, 0.7, 0.45), MATS["orange"], 0.03)
    cube("生活后勤洁污分流总图", (55, 45.6, 1.35), (18, 0.38, 1.9), MATS["panel"], 0.06)
    text("生活后勤洁污分流总图_文字", "食材入库→加工→供餐 / 餐盘回收→洗消 / 宿舍生活服务", (55, 45.35, 1.42), 0.35, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_生活后勤完整运营", (55, 45.6, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_sports_health_detail():
    # Indoor sports hall as a full PE/health facility rather than a single court.
    indoor_z = 8.05
    indoor_nodes = [
        ("体育馆_篮球主场", 55, 11, MATS["wood"]),
        ("体育馆_排球场", 49, 10.5, MATS["orange"]),
        ("体育馆_羽毛球场A", 59.5, 8.0, MATS["green"]),
        ("体育馆_羽毛球场B", 59.5, 13.8, MATS["green"]),
        ("体育馆_乒乓球区", 47.0, 6.0, MATS["blue"]),
        ("体育馆_体测区", 63.0, 6.0, MATS["yellow"]),
        ("体育馆_健身房", 47.0, 16.0, MATS["metal"]),
        ("体育馆_瑜伽舞蹈房", 63.0, 16.0, MATS["purple"]),
    ]
    for name, x, y, material in indoor_nodes:
        cube(name, (x, y, indoor_z), (4.8, 2.3, 0.12), material, 0.025)
        cube(f"设施索引_{name}", (x, y, indoor_z + 0.28), (0.58, 0.58, 0.24), MATS["orange"], 0.018)
    for i, y in enumerate([8.0, 13.8]):
        cube(f"体育馆_羽毛球网_{i}", (59.5, y, indoor_z + 0.42), (4.2, 0.06, 0.55), MATS["metal"], 0.008)
    cube("体育馆_排球网", (49, 10.5, indoor_z + 0.42), (4.2, 0.06, 0.58), MATS["metal"], 0.008)
    for i, x in enumerate([46.0, 47.4, 48.8]):
        cube(f"体育馆_乒乓球台_{i}", (x, 6.0, indoor_z + 0.32), (0.95, 0.55, 0.12), MATS["blue"], 0.012)
    for i, x in enumerate([45.9, 47.0, 48.1]):
        cyl(f"体育馆_健身器械_{i}", (x, 16.0, indoor_z + 0.45), 0.18, 0.7, MATS["metal"], vertices=16)
    for i, x in enumerate([61.5, 62.6, 63.7, 64.8]):
        cube(f"体育馆_体测仪_{i}", (x, 6.0, indoor_z + 0.48), (0.38, 0.32, 0.72), MATS["screen"], 0.018)
    cube("体育馆_可伸缩看台", (55, 18.5, indoor_z + 0.58), (18.5, 1.4, 1.0), MATS["stone"], 0.04)
    for i in range(4):
        cube(f"体育馆_看台座席_{i}", (55, 18.0 + i * 0.32, indoor_z + 0.9 + i * 0.08), (17.4, 0.12, 0.12), MATS["wood"], 0.006)
    cube("体育馆_赛事计分屏", (43.2, 11, indoor_z + 2.1), (0.12, 4.2, 1.6), MATS["screen"], 0.02)
    cube("体育馆_急救AED运动医务点", (44.0, 18.6, indoor_z + 0.55), (1.2, 0.62, 0.85), MATS["red"], 0.03)
    cube("体育馆_饮水补给点", (66.2, 18.6, indoor_z + 0.55), (1.2, 0.62, 0.85), MATS["blue"], 0.03)
    cube("体育馆_运动数据采集屏", (55, 4.0, indoor_z + 1.1), (5.5, 0.12, 1.1), MATS["screen"], 0.02)

    # Outdoor sports completeness: additional courts, fitness trail, and PE storage.
    outdoor_nodes = [
        ("室外排球场", 17, -18, MATS["orange"]),
        ("室外网球场", 28, -18, MATS["green"]),
        ("室外体能训练区", 39, -18, MATS["metal"]),
        ("单双杠训练区", 55, -43, MATS["blue"]),
        ("体育教师办公室", 64, -40, MATS["wood"]),
        ("运动器材发放点", 67, -40, MATS["orange"]),
        ("运动损伤处理点", 70, -40, MATS["red"]),
    ]
    for name, x, y, material in outdoor_nodes:
        cube(name, (x, y, 0.22), (7.2 if "场" in name else 2.4, 4.2 if "场" in name else 1.5, 0.12 if "场" in name else 1.1), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.62), (0.78, 0.78, 0.42), MATS["orange"], 0.025)
    for i, x in enumerate([35.8, 38.0, 40.2, 42.4]):
        cyl(f"室外体能训练器械_{i}", (x, -18, 0.78), 0.08, 1.3, MATS["metal"], vertices=12)
    for i, x in enumerate([52.8, 54.2, 55.6, 57.0]):
        cyl(f"单双杠立柱_{i}", (x, -43, 0.9), 0.07, 1.6, MATS["metal"], vertices=12)
    for i, (x, y) in enumerate([(14, -33), (22, -45), (38, -45), (60, -34), (63, -22)]):
        cube(f"夜跑步道照明_{i}", (x, y, 1.6), (0.16, 0.16, 3.0), MATS["metal"], 0.01)
        cube(f"夜跑步道灯头_{i}", (x, y + 0.28, 3.15), (0.62, 0.18, 0.16), MATS["light"], 0.02)
    cube("运动健康总览牌", (61, -48.5, 1.25), (18, 0.38, 1.8), MATS["panel"], 0.06)
    text("运动健康总览牌_文字", "体育健康：室内多功能场馆 / 室外田赛球类 / 体测健身 / AED与运动医务", (61, -48.75, 1.35), 0.32, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_体育健康完整系统", (61, -48.5, 2.35), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_labels_and_legend():
    cube("legend panel", (-65, 47, 0.9), (18, 0.35, 1.8), MATS["panel"], 0.06)
    text("legend title", "智慧校园总图图例", (-65, 46.78, 1.5), 0.55, MATS["light"], rot=(math.radians(90), 0, 0))
    text("legend body", "红砖=教学建筑  蓝=网络光纤  黄=电力系统  深色=安防/机房", (-65, 46.75, 0.85), 0.38, MATS["white"], rot=(math.radians(90), 0, 0))
    text("campus title", "南京外国语学校风格 · 现代化学校完整地图", (0, 51, 0.15), 1.5, MATS["white"])
    text("design basis label", "原型语言：红砖校园、半环入口、院落组团、动静分离、中心水景", (0, 47.7, 0.15), 0.85, MATS["white"])
    facility_points = [
        ("设施索引_保安室", -14, -53.2),
        ("设施索引_监控室", -36, -7),
        ("设施索引_配电室", -57, -7),
        ("设施索引_服务器机房", -36, -22),
        ("设施索引_微机室", -57, -22),
        ("设施索引_普通教室组团", -12, 12),
        ("设施索引_科技运维楼", -48, -21),
        ("设施索引_STEM中心", -23, -24),
        ("设施索引_图书馆", 0, -21),
        ("设施索引_食堂", 30, 31),
        ("设施索引_宿舍", 54, 31),
        ("设施索引_操场", 45, -28),
        ("设施索引_室内操场_体育馆", 55, 11),
        ("设施索引_室外变配电区", -62, 28),
        ("设施索引_中心水景", 0, -2),
    ]
    for name, x, y in facility_points:
        cube(name, (x, y, 0.35), (1.0, 1.0, 0.55), MATS["orange"], 0.04)


def setup_camera_lights():
    bpy.ops.object.light_add(type="SUN", location=(-40, -50, 80))
    sun = bpy.context.object
    sun.name = "campus sun"
    sun.data.energy = 2.3
    sun.rotation_euler = (math.radians(48), 0, math.radians(-35))
    for x, y in [(-35, -20), (20, -15), (45, 25), (-45, 30)]:
        bpy.ops.object.light_add(type="AREA", location=(x, y, 12))
        l = bpy.context.object
        l.name = f"soft campus fill light {x} {y}"
        l.data.energy = 260
        l.data.size = 18
    bpy.ops.object.camera_add(location=(82, -86, 58))
    cam = bpy.context.object
    cam.name = "campus aerial overview camera"
    direction = Vector((0, -4, 0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 24
    bpy.context.scene.camera = cam
    bpy.context.scene.render.engine = "CYCLES"
    bpy.context.scene.cycles.samples = 64
    bpy.context.scene.render.resolution_x = 1800
    bpy.context.scene.render.resolution_y = 1200
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.view_settings.look = "Medium High Contrast"
    bpy.context.scene.world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world.color = (0.78, 0.86, 0.92)


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


PREVIEW_VIEWS = [
    ("01_校园鸟瞰总图", (82, -86, 58), (0, -4, 0), 24),
    ("02_入口半环与保安室", (24, -78, 17), (0, -48, 2), 30),
    ("03_科技楼机房配电监控", (-78, -34, 20), (-47, -14, 1), 28),
    ("04_教学院落和中心水景", (42, -30, 25), (-5, 4, 1), 26),
    ("05_操场和室内体育馆", (78, -62, 30), (45, -14, 1), 27),
    ("06_生活组团与后勤能源", (10, 66, 25), (18, 28, 1), 30),
    ("07_STEM实验和创新空间", (-45, -44, 18), (-23, -24, 1), 30),
    ("08_交通消防能源系统", (-74, -72, 26), (-24, -32, 1), 26),
    ("09_楼内剖面和管廊", (74, 58, 34), (15, 13, 4), 28),
    ("10_后勤边界和服务节点", (88, 74, 34), (48, 30, 2), 30),
    ("11_图书体育公共服务", (64, -6, 28), (22, -14, 5), 30),
    ("12_规划行政实验安全运动", (-76, 62, 31), (-20, 12, 3), 28),
    ("13_地图索引图层控制", (-88, 32, 24), (-48, 24, 2), 30),
    ("14_教学楼容量与智慧教室", (66, 34, 24), (30, 12, 6), 34),
    ("15_生活后勤食堂宿舍运营", (84, 58, 24), (52, 35, 4), 30),
    ("16_体育健康室内外系统", (84, -56, 26), (52, -18, 4), 30),
]


def render_previews():
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for f in os.listdir(PREVIEW_DIR):
        if f.endswith(".png"):
            os.remove(os.path.join(PREVIEW_DIR, f))
    try:
        bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
    bpy.context.scene.render.resolution_x = 1400
    bpy.context.scene.render.resolution_y = 900
    for name, loc, target, lens in PREVIEW_VIEWS:
        cam_data = bpy.data.cameras.new(f"preview camera {name}")
        cam = bpy.data.objects.new(f"preview camera {name}", cam_data)
        bpy.context.collection.objects.link(cam)
        cam.location = loc
        look_at(cam, target)
        cam.data.lens = lens
        bpy.context.scene.camera = cam
        bpy.context.scene.render.filepath = os.path.join(PREVIEW_DIR, f"{name}.png")
        bpy.ops.render.render(write_still=True)
    make_contact_sheet()


def make_contact_sheet():
    script = f"""
import os
from PIL import Image, ImageDraw
out_dir = {PREVIEW_DIR!r}
files = [os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir)) if f.endswith('.png') and f[:2].isdigit()]
thumb_w, thumb_h = 560, 360
cols = 2
rows = (len(files) + cols - 1) // cols
sheet = Image.new('RGB', (cols * thumb_w, rows * (thumb_h + 34)), (236, 236, 236))
draw = ImageDraw.Draw(sheet)
for idx, path in enumerate(files):
    img = Image.open(path).convert('RGB')
    img.thumbnail((thumb_w, thumb_h), Image.LANCZOS)
    x = (idx % cols) * thumb_w + (thumb_w - img.width) // 2
    y = (idx // cols) * (thumb_h + 34)
    sheet.paste(img, (x, y))
    draw.text(((idx % cols) * thumb_w + 14, y + thumb_h + 8), f'campus view {{idx + 1:02d}}', fill=(20, 20, 20))
sheet.save(os.path.join(out_dir, '00_校园总览拼图.png'))
"""
    subprocess.run(["python3", "-c", script], check=True)


def build_scene():
    clear_scene()
    init_materials()
    make_campus_base()
    make_gate_and_security()
    make_academic_core()
    make_technology_building()
    make_science_and_innovation_spaces()
    make_sports_and_living()
    make_service_and_safety()
    make_transport_and_access()
    make_smart_safety_energy_systems()
    make_cutaway_interiors_and_tunnels()
    make_daily_school_services()
    make_public_amenities_and_special_interiors()
    make_planning_admin_and_learning_landscape()
    make_map_index_and_system_layers()
    make_teaching_detail_and_capacity_schedule()
    make_living_logistics_detail()
    make_sports_health_detail()
    make_labels_and_legend()
    setup_camera_lights()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    render_previews()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


if __name__ == "__main__":
    build_scene()
