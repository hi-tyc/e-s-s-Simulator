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
    make_labels_and_legend()
    setup_camera_lights()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    render_previews()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


if __name__ == "__main__":
    build_scene()
