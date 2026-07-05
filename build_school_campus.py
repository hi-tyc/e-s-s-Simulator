import math
import os
import subprocess

import bpy
from mathutils import Vector


ROOT = os.environ.get("SCHOOL_ROOT", os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.environ.get("SCHOOL_BLEND", os.path.join(ROOT, "school_campus.blend"))
PREVIEW_DIR = os.environ.get("SCHOOL_PREVIEW_DIR", os.path.join(ROOT, "campus_previews"))
SKIP_PREVIEWS = os.environ.get("SCHOOL_SKIP_PREVIEWS", "").lower() in {"1", "true", "yes"}


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


def make_fangshan_public_reference_reconstruction():
    # Public-source reconstruction anchors from GLA/ArchDaily/ArchCollege descriptions and plan imagery.
    cube("南外方山公开资料复刻_学苑方城总平基准框", (0, -2, 0.155), (126, 86, 0.03), MATS["stone"])
    cube("南外方山公开资料复刻_南北礼仪轴", (0, -2, 0.24), (3.0, 88, 0.055), MATS["orange"])
    cube("南外方山公开资料复刻_东西学习街轴", (0, -8, 0.255), (108, 2.4, 0.055), MATS["blue"])
    cube("南外方山公开资料复刻_生活运动分离界面", (43, 3, 0.27), (2.0, 76, 0.055), MATS["green"])
    cyl("南外方山公开资料复刻_中心水景圆庭", (0, -2, 0.31), 10.2, 0.06, MATS["water"], vertices=32)
    cyl("南外方山公开资料复刻_中心水景环形步道", (0, -2, 0.335), 12.0, 0.035, MATS["paving"], vertices=32)

    text("南外方山公开资料复刻_总平概念文字", "公开资料复刻：学苑方城 / 南北双轴 / 院落教学 / 生活运动分离 / 红砖暖白", (0, 42.2, 0.35), 0.72, MATS["white"])

    source_panels = [
        ("公开资料来源_ArchDaily_南外方山_GLA_项目页", -56, -36, "ArchDaily：南京外国语学校方山校区 / GLA建筑设计，2018，164406㎡"),
        ("公开资料来源_GLA官网_南外方山_项目页", -56, -33.4, "GLA官网：弘景大道与方山景区之间，用地233646㎡，建筑226859㎡，容积率0.84"),
        ("公开资料来源_建筑学院_南外方山_转载图文", -56, -30.8, "建筑学院：西方公学尺度、当代多元文化、院落化校园、红砖城市展示面"),
    ]
    for name, x, y, label in source_panels:
        cube(name, (x, y, 1.15), (22.0, 0.34, 1.5), MATS["panel"], 0.015)
        text(f"{name}_文字", label, (x, y - 0.22, 1.18), 0.23, MATS["white"], rot=(math.radians(90), 0, 0))
        cube(f"设施索引_{name}", (x - 11.8, y, 0.42), (0.85, 0.85, 0.48), MATS["orange"], 0.01)

    campus_bands = [
        ("公开总平_入口共享学苑带", 0, -37, 47, 14, MATS["orange"], "入口共享学苑"),
        ("公开总平_小学初中组团带", -37, 4, 23, 19, MATS["blue"], "小初组团院落"),
        ("公开总平_高中部组团带", -12, 12, 23, 19, MATS["purple"], "高中组团院落"),
        ("公开总平_国际部组团带", 14, 12, 23, 19, MATS["green"], "国际部组团院落"),
        ("公开总平_共享教室组团带", 40, 4, 23, 19, MATS["yellow"], "共享教室组团"),
        ("公开总平_生活住宿餐饮带", 46, 32, 38, 19, MATS["green"], "生活后勤组团"),
        ("公开总平_运动活力带", 50, -30, 48, 24, MATS["red"], "运动活力组团"),
    ]
    for name, x, y, w, d, material, label in campus_bands:
        cube(name, (x, y, 0.38), (w, d, 0.04), material)
        text(f"{name}_功能文字", label, (x, y, 0.48), 0.34, MATS["white"])

    ring_center = (0, -45)
    for i, angle in enumerate(range(198, 343, 16)):
        rad = math.radians(angle)
        x = ring_center[0] + math.cos(rad) * 26.8
        y = ring_center[1] + math.sin(rad) * 26.8
        cube(f"公开平面图_半敞开环形入口艺苑控制线_{i}", (x, y, 0.44), (1.45, 0.08, 0.12), MATS["yellow"], rot_z=rad + math.pi / 2)

    learning_street_nodes = [(-38, 4), (-12, 12), (14, 12), (40, 4)]
    for idx, (x, y) in enumerate(learning_street_nodes):
        cube(f"公开资料复刻_院落组团_{idx}_暗红面砖连续檐廊", (x, y - 7.0, 1.65), (16.8, 0.52, 1.35), MATS["brick"], 0.01)
        cube(f"公开资料复刻_院落组团_{idx}_暖白石材门套", (x, y - 7.32, 1.35), (5.2, 0.22, 1.95), MATS["stone"], 0.01)
        cube(f"公开资料复刻_院落组团_{idx}_共享学习街玻璃面", (x, y + 6.28, 1.85), (15.2, 0.18, 2.4), MATS["glass"])
        for bay in range(5):
            bx = x - 6.4 + bay * 3.2
            cube(f"公开资料复刻_院落组团_{idx}_红砖竖向窗间墙_{bay}", (bx, y - 6.95, 2.7), (0.34, 0.42, 3.1), MATS["brick"])
            cube(f"公开资料复刻_院落组团_{idx}_竖向绿化钢索_{bay}", (bx + 0.55, y - 7.24, 2.45), (0.055, 0.055, 2.8), MATS["green"])
        cyl(f"公开资料复刻_院落组团_{idx}_内院树池", (x, y, 0.52), 4.8, 0.18, MATS["paving"], vertices=24)
        cyl(f"公开资料复刻_院落组团_{idx}_内院草坪", (x, y, 0.64), 3.55, 0.12, MATS["grass"], vertices=24)

    source_features = [
        ("公开特征_暗红色面砖主材", -64, 12, MATS["brick"]),
        ("公开特征_暖白色石材基座", -64, 15, MATS["stone"]),
        ("公开特征_院落化校园空间", -64, 18, MATS["green"]),
        ("公开特征_第三代学校共享学习空间", -64, 21, MATS["screen"]),
        ("公开特征_山水校园方山背景", -64, 24, MATS["mountain"]),
    ]
    for name, x, y, material in source_features:
        cube(name, (x, y, 1.05), (6.8, 0.38, 1.25), material, 0.01)
        text(f"{name}_说明文字", name.replace("公开特征_", ""), (x, y - 0.25, 1.1), 0.24, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_南外方山公开资料复刻层", (-64, 18, 2.05), (1.0, 1.0, 0.45), MATS["orange"], 0.01)


def make_fangshan_high_fidelity_public_details():
    # Second-pass public-source fidelity layer: turns published descriptions/photos into concrete facade, section, and interior cues.
    detail_panels = [
        ("南外方山高相似复刻_公开关键词_学苑方城", -63, 30, "学苑方城：以方正校园肌理组织教学/生活/运动"),
        ("南外方山高相似复刻_公开关键词_第三代学校", -63, 32.4, "第三代学校：非结构化学习空间、共享学习街、开放交流"),
        ("南外方山高相似复刻_公开关键词_公学式校园", -63, 34.8, "公学式校园：红砖立面、院落尺度、城市展示面"),
        ("南外方山高相似复刻_公开关键词_四学部", -63, 37.2, "四学部：小学/初中/高中/国际高中分区组织"),
        ("南外方山高相似复刻_公开关键词_室内深化", -63, 39.6, "室内深化公开标段：教学楼/综合楼/生活楼室内界面继续细化"),
    ]
    for name, x, y, label in detail_panels:
        cube(name, (x, y, 1.12), (19.5, 0.34, 1.36), MATS["panel"], 0.01)
        text(f"{name}_文字", label, (x, y - 0.22, 1.15), 0.22, MATS["white"], rot=(math.radians(90), 0, 0))

    school_sections = [
        ("小学部", 40, 4, MATS["yellow"], 3.6),
        ("初中部", -38, 4, MATS["blue"], 4.2),
        ("高中部", -12, 12, MATS["purple"], 4.8),
        ("国际高中部", 14, 12, MATS["green"], 4.5),
    ]
    for name, x, y, material, height in school_sections:
        cube(f"南外方山高相似复刻_{name}_学部铭牌", (x - 7.2, y - 8.0, 1.55), (0.28, 2.5, 1.5), material, 0.01)
        text(f"南外方山高相似复刻_{name}_学部文字", name, (x - 7.38, y - 8.0, 1.62), 0.28, MATS["white"], rot=(math.radians(90), 0, math.radians(90)))
        cube(f"南外方山高相似复刻_{name}_错落屋面标高", (x + 6.8, y + 5.6, height + 0.22), (4.8, 2.4, 0.18), MATS["roof"], 0.01)
        cube(f"南外方山高相似复刻_{name}_暖白连廊端头", (x + 8.75, y - 1.8, 2.3), (0.32, 5.8, 2.6), MATS["stone"], 0.01)

    facade_bands = [
        ("南侧城市展示红砖表皮", 0, -36.2, 54, 0.22),
        ("西侧教学组团红砖表皮", -49.2, 5.6, 0.22, 28),
        ("东侧生活运动红砖表皮", 50.5, 17.5, 0.22, 35),
    ]
    for name, x, y, w, d in facade_bands:
        cube(f"南外方山高相似复刻_{name}", (x, y, 2.35), (w, d, 3.2), MATS["brick"], 0.01)
        count = 13 if w > d else 8
        for i in range(count):
            if w > d:
                bx = x - w / 2 + 2.2 + i * max(1.0, (w - 4.4) / max(1, count - 1))
                by = y - 0.16
                size = (0.32, 0.08, 2.55)
            else:
                bx = x - 0.16
                by = y - d / 2 + 2.0 + i * max(1.0, (d - 4.0) / max(1, count - 1))
                size = (0.08, 0.32, 2.55)
            cube(f"南外方山高相似复刻_{name}_竖向窗洞_{i}", (bx, by, 2.55), size, MATS["glass"])

    nonformal_nodes = [
        ("非结构化学习台阶_高中共享街", -12, 5.8),
        ("非结构化学习台阶_国际部共享街", 14, 5.8),
        ("非结构化学习台阶_初中共享街", -38, -2.2),
        ("非结构化学习台阶_小学共享街", 40, -2.2),
    ]
    for name, x, y in nonformal_nodes:
        for step in range(4):
            cube(f"南外方山高相似复刻_{name}_{step}", (x, y + step * 0.55, 0.38 + step * 0.12), (5.6 - step * 0.55, 0.42, 0.18), MATS["wood"], 0.01)
        cube(f"南外方山高相似复刻_{name}_学习白板", (x + 3.15, y + 1.0, 1.55), (0.12, 1.7, 1.1), MATS["white"], 0.01)
        cube(f"南外方山高相似复刻_{name}_电子讨论屏", (x - 3.15, y + 1.0, 1.55), (0.12, 1.4, 0.85), MATS["screen"], 0.01)

    interior_bands = [
        ("教学楼室内深化_走廊吊顶灯带", -12, 12),
        ("综合楼室内深化_图书行政共享厅", 0, -21),
        ("生活楼室内深化_宿舍公共客厅", 54, 31),
    ]
    for name, x, y in interior_bands:
        cube(f"南外方山高相似复刻_{name}_天花格栅", (x, y, 6.95), (9.5, 0.18, 0.12), MATS["wood"], 0.005)
        cube(f"南外方山高相似复刻_{name}_暖光灯槽", (x, y + 0.42, 6.9), (9.5, 0.08, 0.08), MATS["light"], 0.004)
        cube(f"南外方山高相似复刻_{name}_室内导视牌", (x - 4.4, y + 0.75, 6.25), (1.35, 0.08, 0.7), MATS["screen"], 0.006)

    cube("南外方山高相似复刻_公开平立剖索引牌", (62, 44, 1.28), (22.0, 0.36, 1.8), MATS["panel"], 0.02)
    text(
        "南外方山高相似复刻_公开平立剖索引牌_文字",
        "二轮细化：四学部/红砖城市展示面/错落标高/共享学习街/非结构化学习/室内深化标段",
        (62, 43.76, 1.34),
        0.25,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_南外方山高相似公开细化层", (62, 44, 2.42), (1.0, 1.0, 0.42), MATS["orange"], 0.01)


def make_fangshan_program_courtyard_details():
    # Third-pass public-detail layer: visible curriculum, courtyard-arch, arts, science, and residential-college cues from public pages.
    arch_specs = [
        ("高中院落庭院拱", -12, 18.9, 0),
        ("国际部院落庭院拱", 14, 18.9, 0),
        ("初中院落庭院拱", -38, 10.9, 0),
        ("小学共享院落庭院拱", 40, 10.9, 0),
        ("入口艺苑连续庭院拱_西", -10.5, -49.0, math.radians(18)),
        ("入口艺苑连续庭院拱_东", 10.5, -49.0, math.radians(-18)),
    ]
    for name, x, y, rot in arch_specs:
        cube(f"南外方山公开课程庭院细节_{name}_左拱脚", (x - 1.15, y, 1.25), (0.34, 0.34, 2.5), MATS["brick"], 0.01, rot_z=rot)
        cube(f"南外方山公开课程庭院细节_{name}_右拱脚", (x + 1.15, y, 1.25), (0.34, 0.34, 2.5), MATS["brick"], 0.01, rot_z=rot)
        cube(f"南外方山公开课程庭院细节_{name}_拱券梁", (x, y, 2.62), (2.65, 0.34, 0.38), MATS["brick"], 0.01, rot_z=rot)
        cyl(f"南外方山公开课程庭院细节_{name}_半圆拱心", (x, y - 0.02, 2.46), 0.52, 0.12, MATS["stone"], vertices=16, rot=(math.radians(90), 0, rot))

    curriculum_rooms = [
        ("A-Level课程教室", 10.6, 13.8, MATS["blue"]),
        ("AP课程教室", 14.0, 13.8, MATS["purple"]),
        ("OSSD课程教室", 17.4, 13.8, MATS["green"]),
        ("国际升学指导中心", 20.8, 13.8, MATS["screen"]),
        ("英语戏剧黑盒", 17.4, 9.5, MATS["purple"]),
        ("跨文化项目展示墙", 10.6, 9.5, MATS["orange"]),
    ]
    for name, x, y, material in curriculum_rooms:
        cube(f"南外方山公开课程庭院细节_{name}_房间牌", (x, y, 3.18), (2.25, 0.16, 0.68), material, 0.01)
        cube(f"南外方山公开课程庭院细节_{name}_室内桌组", (x, y - 0.55, 2.82), (1.55, 0.72, 0.18), MATS["white"], 0.006)
        cube(f"南外方山公开课程庭院细节_{name}_教学屏", (x, y + 0.72, 3.05), (1.3, 0.08, 0.72), MATS["screen"], 0.006)

    arts_science_nodes = [
        ("美育中心_画室天窗", 23.0, -26.4, MATS["orange"]),
        ("美育中心_舞蹈排练镜墙", 26.4, -26.4, MATS["purple"]),
        ("美育中心_音乐排练琴房", 29.8, -26.4, MATS["wood"]),
        ("科学竞赛实验室_物理", -27.8, -26.0, MATS["blue"]),
        ("科学竞赛实验室_化学", -23.0, -26.0, MATS["green"]),
        ("科学竞赛实验室_生物", -18.2, -26.0, MATS["purple"]),
    ]
    for name, x, y, material in arts_science_nodes:
        cube(f"南外方山公开课程庭院细节_{name}_功能盒", (x, y, 2.7), (2.45, 1.35, 0.8), material, 0.015)
        cube(f"南外方山公开课程庭院细节_{name}_开放展示面", (x, y - 0.72, 2.75), (1.8, 0.08, 0.68), MATS["glass"], 0.006)

    houses = [
        ("宿舍学院制_House_A", 47.0, 33.8, MATS["blue"]),
        ("宿舍学院制_House_B", 52.0, 33.8, MATS["green"]),
        ("宿舍学院制_House_C", 57.0, 33.8, MATS["purple"]),
        ("宿舍学院制_House_D", 62.0, 33.8, MATS["orange"]),
    ]
    for name, x, y, material in houses:
        cube(f"南外方山公开课程庭院细节_{name}_学院客厅", (x, y, 6.92), (3.6, 2.2, 0.22), material, 0.01)
        cube(f"南外方山公开课程庭院细节_{name}_公告板", (x, y + 1.18, 7.4), (2.5, 0.08, 0.72), MATS["screen"], 0.006)
        cube(f"南外方山公开课程庭院细节_{name}_共享长桌", (x, y, 7.15), (2.2, 0.72, 0.14), MATS["wood"], 0.006)

    division_curriculum = [
        ("小学部_美育活动课程", 40, -5.2, MATS["yellow"]),
        ("初中部_科创拓展课程", -38, -5.2, MATS["blue"]),
        ("高中部_竞赛拔尖课程", -12, 2.6, MATS["purple"]),
        ("国际高中部_国际课程路径", 14, 2.6, MATS["green"]),
    ]
    for name, x, y, material in division_curriculum:
        cube(f"南外方山公开课程庭院细节_{name}_课程地图", (x, y, 1.22), (6.2, 0.32, 1.46), MATS["panel"], 0.015)
        cube(f"南外方山公开课程庭院细节_{name}_课程色带", (x, y - 0.2, 1.68), (5.3, 0.08, 0.18), material, 0.004)
        text(f"南外方山公开课程庭院细节_{name}_文字", name, (x, y - 0.25, 1.2), 0.24, MATS["white"], rot=(math.radians(90), 0, 0))

    cube("南外方山公开课程庭院细节_公开依据索引牌", (-62, 43.2, 1.3), (22.0, 0.36, 1.8), MATS["panel"], 0.02)
    text(
        "南外方山公开课程庭院细节_公开依据索引牌_文字",
        "三轮细化：庭院拱/国际课程A-Level AP OSSD/美育中心/科学竞赛/宿舍学院制/四学部课程地图",
        (-62, 42.96, 1.36),
        0.23,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_南外方山公开课程庭院细节层", (-62, 43.2, 2.44), (1.0, 1.0, 0.42), MATS["orange"], 0.01)


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


def make_security_fire_resilience_detail():
    # Smart security and emergency resilience layer: sensing, response, backup power, and shelter supplies.
    security_nodes = [
        ("周界入侵探测器_北西", -52, 54.7, MATS["screen"]),
        ("周界入侵探测器_北中", 0, 54.7, MATS["screen"]),
        ("周界入侵探测器_北东", 52, 54.7, MATS["screen"]),
        ("周界入侵探测器_西侧", -74.7, 12, MATS["screen"]),
        ("周界入侵探测器_东侧", 74.7, 12, MATS["screen"]),
        ("访客证件核验终端", -10.5, -52.3, MATS["screen"]),
        ("车辆道闸车牌识别", -4.5, -55.0, MATS["screen"]),
        ("电子巡更点_教学区", -18, 18, MATS["yellow"]),
        ("电子巡更点_生活区", 44, 38, MATS["yellow"]),
        ("电子巡更点_运动区", 62, -38, MATS["yellow"]),
    ]
    for name, x, y, material in security_nodes:
        cube(name, (x, y, 1.28), (0.72, 0.42, 1.45), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.42), (0.72, 0.72, 0.42), MATS["orange"], 0.025)

    for i, (x, y) in enumerate([(-38, 11), (-12, 19), (14, 19), (40, 11), (0, -17), (55, 19), (30, 36), (54, 37)]):
        cube(f"消防报警手报按钮_{i}", (x, y, 1.15), (0.32, 0.18, 0.45), MATS["red"], 0.018)
        cyl(f"烟感探测器_{i}", (x + 0.5, y, 2.25), 0.16, 0.06, MATS["white"], vertices=20)
        cube(f"应急照明疏散指示_{i}", (x - 0.5, y, 1.95), (0.58, 0.12, 0.22), MATS["light"], 0.012)
    for i, (x, y, length, rot_z) in enumerate([(-25, 8, 22, 0), (1, 12, 22, 0), (27, 8, 22, 0), (-6, -6, 34, math.radians(-28))]):
        cube(f"连廊防火卷帘_{i}", (x, y, 2.35), (length * 0.22, 0.16, 0.75), MATS["red"], 0.012, rot_z=rot_z)
    cube("消防报警联动主机", (-36, -11.9, 2.1), (1.4, 0.18, 1.0), MATS["red"], 0.025)
    cube("安防事件联动平台", (-37.8, -11.9, 2.1), (1.4, 0.18, 1.0), MATS["screen"], 0.025)

    resilience_nodes = [
        ("应急物资仓库", -23, -39, MATS["yellow"]),
        ("临时避险棚", -14, -39, MATS["white"]),
        ("移动发电车接口", -5, -39, MATS["metal"]),
        ("卫星通信终端", 4, -39, MATS["screen"]),
        ("校园无线应急基站", 13, -39, MATS["blue"]),
        ("UPS不间断电源室", -47, 23, MATS["panel"]),
        ("储能电池舱", -51, 23, MATS["solar"]),
        ("微电网切换柜", -55, 23, MATS["yellow"]),
        ("应急净水装置", -69, 27, MATS["water"]),
        ("医疗救护集结帐篷", 18, -39, MATS["red"]),
    ]
    for name, x, y, material in resilience_nodes:
        cube(name, (x, y, 1.1), (3.2, 1.8, 1.7), material, 0.05)
        cube(f"设施索引_{name}", (x, y, 0.4), (0.78, 0.78, 0.45), MATS["orange"], 0.03)
    for i, (x1, y1, x2, y2, material) in enumerate([
        (-47, 23, -36, -7, MATS["yellow"]),
        (-51, 23, -18, -9, MATS["solar"]),
        (13, -39, -36, -7, MATS["blue"]),
        (4, -39, -36, -7, MATS["screen"]),
    ]):
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(f"韧性系统联动线_{i}", ((x1 + x2) / 2, (y1 + y2) / 2, 0.48), (length, 0.16, 0.06), material, 0.006, rot_z=angle)

    cube("校园应急指挥中心", (-36, -3.6, 2.8), (7.6, 0.18, 1.2), MATS["screen"], 0.025)
    text("校园应急指挥中心_文字", "应急指挥：安防/消防/广播/门禁/储能/通信联动", (-36, -3.78, 2.92), 0.28, MATS["light"], rot=(math.radians(90), 0, 0))
    cube("智慧安全韧性总览牌", (-26, -43.5, 1.35), (24, 0.38, 1.9), MATS["panel"], 0.06)
    text("智慧安全韧性总览牌_文字", "智慧安全韧性：周界探测 / 门禁联动 / 消防报警 / 避险物资 / UPS微电网", (-26, -43.75, 1.42), 0.32, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_智慧安全韧性系统", (-26, -43.5, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_low_carbon_science_operations():
    # Low-carbon operations and environmental science layer for a measurable modern campus.
    energy_nodes = [
        ("光伏逆变器组", 6, -27.5, MATS["solar"]),
        ("光伏汇流箱", 10, -27.5, MATS["yellow"]),
        ("碳排能耗看板", 14, -27.5, MATS["screen"]),
        ("楼宇能耗分项计量柜", 18, -27.5, MATS["panel"]),
        ("电动车充电桩_访客", -42, -52.8, MATS["green"]),
        ("电动车充电桩_教工", -52, 46.4, MATS["green"]),
        ("校车充电桩", -19, -55.0, MATS["green"]),
    ]
    for name, x, y, material in energy_nodes:
        cube(name, (x, y, 1.05), (1.3, 0.72, 1.55), material, 0.04)
        cube(f"设施索引_{name}", (x, y, 0.36), (0.72, 0.72, 0.42), MATS["orange"], 0.025)
    for i, (x1, y1, x2, y2) in enumerate([(6, -27.5, -51, 23), (14, -27.5, -36, -7), (-19, -55, -47, 23)]):
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(f"低碳能源数据线_{i}", ((x1 + x2) / 2, (y1 + y2) / 2, 0.52), (length, 0.14, 0.055), MATS["green"], 0.006, rot_z=angle)

    water_nodes = [
        ("雨水回用泵房", -71, 42.5, MATS["blue"]),
        ("中水处理设备", -66.5, 45.5, MATS["water"]),
        ("透水铺装样板区", -31, 43.5, MATS["paving"]),
        ("智能灌溉阀箱", -14, 38.5, MATS["green"]),
        ("土壤湿度传感器", -9, 39.8, MATS["screen"]),
        ("水质在线监测站", -2, -2, MATS["screen"]),
    ]
    for name, x, y, material in water_nodes:
        cube(name, (x, y, 0.92), (2.1, 1.25, 1.35), material, 0.045)
        cube(f"设施索引_{name}", (x, y, 0.34), (0.72, 0.72, 0.42), MATS["orange"], 0.025)
    for i, (x, y) in enumerate([(-38, 40.5), (-32, 40.5), (-26, 40.5), (-18, 38.5), (-10, 38.5), (8, 38.0)]):
        cyl(f"智能灌溉喷头_{i}", (x, y, 0.32), 0.16, 0.12, MATS["blue"], vertices=18)

    ecology_nodes = [
        ("校园生物多样性样方", -44, 44.5, MATS["wetland"]),
        ("昆虫旅馆", -41, 43.1, MATS["wood"]),
        ("鸟类观察点", -36, 43.3, MATS["green"]),
        ("屋顶绿化实验田", 25, -21, MATS["green"]),
        ("热岛温度传感器", 0, 30, MATS["screen"]),
        ("噪声监测站_校门", -2, -54.5, MATS["screen"]),
        ("噪声监测站_操场", 35, -43, MATS["screen"]),
        ("微气候观测塔", -58, 40.5, MATS["metal"]),
    ]
    for name, x, y, material in ecology_nodes:
        cube(name, (x, y, 1.0), (2.2, 1.2, 1.35), material, 0.045)
        cube(f"设施索引_{name}", (x, y, 0.34), (0.72, 0.72, 0.42), MATS["orange"], 0.025)
    cyl("微气候观测塔_风廓线杆", (-58, 40.5, 3.2), 0.08, 4.0, MATS["metal"], vertices=12)
    for i, z in enumerate([2.3, 3.1, 3.9]):
        cube(f"微气候观测塔_传感器_{i}", (-57.6, 40.5, z), (0.42, 0.2, 0.28), MATS["screen"], 0.015)

    cube("科学运维数字孪生看板", (-48, 48.6, 1.45), (24, 0.42, 2.1), MATS["screen"], 0.06)
    text("科学运维数字孪生看板_文字", "低碳科学运维：光伏/储能/充电/雨洪回用/水质/噪声/热岛/生物多样性", (-48, 48.32, 1.52), 0.32, MATS["light"], rot=(math.radians(90), 0, 0))
    cube("设施索引_低碳生态科学运维", (-48, 48.6, 2.65), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_culture_arts_student_center():
    # Cultural, media, and club spaces make the liberal-arts side read as a complete student public center.
    arts_nodes = [
        ("黑匣子剧场", 18.0, -17.2, MATS["panel"]),
        ("小剧场舞台", 22.0, -17.2, MATS["wood"]),
        ("合唱排练室", 26.0, -17.2, MATS["purple"]),
        ("乐器库", 29.5, -17.2, MATS["wood"]),
        ("舞蹈排练厅", 18.0, -21.2, MATS["purple"]),
        ("美术展廊", 22.0, -21.2, MATS["orange"]),
        ("陶艺工作室", 26.0, -21.2, MATS["stone"]),
        ("服装道具库", 29.5, -21.2, MATS["metal"]),
    ]
    for name, x, y, material in arts_nodes:
        cube(name, (x, y, 5.42), (2.9, 1.65, 0.18), material, 0.026)
        cube(f"设施索引_{name}", (x, y, 5.72), (0.56, 0.56, 0.28), MATS["orange"], 0.02)
    for i, x in enumerate([18.6, 19.4, 20.2, 24.8, 25.6, 26.4]):
        cyl(f"乐器库_乐器架_{i}", (x, -16.6, 5.72), 0.12, 0.68, MATS["metal"], vertices=12)
    for i, x in enumerate([20.6, 22.0, 23.4]):
        cube(f"美术展廊_展墙_{i}", (x, -20.45, 5.72), (0.9, 0.08, 0.58), MATS["white"], 0.01)

    media_nodes = [
        ("校园广播站", -7.5, -20.3, MATS["screen"]),
        ("电视台演播室", -4.5, -20.3, MATS["screen"]),
        ("录音棚", -1.5, -20.3, MATS["panel"]),
        ("融媒体剪辑室", 1.5, -20.3, MATS["blue"]),
        ("学生会办公室", 4.5, -20.3, MATS["wood"]),
        ("社团活动室_A", -7.5, -16.5, MATS["green"]),
        ("社团活动室_B", -4.5, -16.5, MATS["green"]),
        ("社团活动室_C", -1.5, -16.5, MATS["green"]),
        ("社团活动室_D", 1.5, -16.5, MATS["green"]),
        ("校园融媒体发布屏", 4.5, -16.5, MATS["screen"]),
    ]
    for name, x, y, material in media_nodes:
        cube(name, (x, y, 6.92), (2.15, 1.35, 0.16), material, 0.024)
        cube(f"设施索引_{name}", (x, y, 7.18), (0.52, 0.52, 0.26), MATS["orange"], 0.018)
    for i, x in enumerate([-7.9, -7.1, -4.9, -4.1]):
        cube(f"融媒体_声光设备_{i}", (x, -19.75, 7.12), (0.36, 0.28, 0.36), MATS["metal"], 0.012)

    plaza_nodes = [
        ("学生作品展示长廊", 8, -33.5, MATS["white"]),
        ("社团招新广场", 14, -33.5, MATS["orange"]),
        ("校园文化墙", 20, -33.5, MATS["brick"]),
        ("升旗礼仪广场", 0, -38.5, MATS["paving"]),
        ("校训景观石", -6, -38.5, MATS["stone"]),
        ("公告与活动信息屏", 6, -38.5, MATS["screen"]),
    ]
    for name, x, y, material in plaza_nodes:
        cube(name, (x, y, 0.78), (4.2, 0.72, 1.25), material, 0.045)
        cube(f"设施索引_{name}", (x, y, 0.32), (0.72, 0.72, 0.42), MATS["orange"], 0.025)
    for i, x in enumerate([-3.6, -1.8, 0, 1.8, 3.6]):
        cyl(f"升旗礼仪广场_旗杆_{i}", (x, -37.8, 2.2), 0.06, 4.2, MATS["metal"], vertices=12)
    cube("文化艺术社团总览牌", (11, -41.8, 1.35), (24, 0.38, 1.9), MATS["panel"], 0.06)
    text("文化艺术社团总览牌_文字", "文化艺术：剧场/排练/展廊/融媒体/学生会/社团/升旗礼仪", (11, -42.05, 1.42), 0.32, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_文化艺术社团中心", (11, -41.8, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_transport_accessibility_operations():
    # Arrival and mobility operations: parent pickup, buses, bikes, pedestrians, accessibility, and logistics separation.
    arrival_nodes = [
        ("家长接送即停即走区", (18, -55.0, 0.16), (24, 2.0, 0.08), MATS["road"]),
        ("家长等候雨棚", (18, -51.8, 1.85), (18, 2.2, 0.26), MATS["roof"]),
        ("学生排队缓冲区", (4, -49.0, 0.18), (12, 3.0, 0.08), MATS["paving"]),
        ("访客登记落客点", (-11.5, -49.3, 0.2), (4.6, 2.2, 0.08), MATS["orange"]),
        ("校车候车雨棚", (-32, -51.2, 1.85), (24, 2.2, 0.26), MATS["roof"]),
        ("共享单车停放区", (43, -52.8, 0.18), (8.4, 2.4, 0.08), MATS["paving"]),
    ]
    for name, loc, size, material in arrival_nodes:
        cube(name, loc, size, material, 0.04)
        cube(f"设施索引_{name}", (loc[0], loc[1], 0.48), (0.78, 0.78, 0.42), MATS["orange"], 0.025)
    for i, x in enumerate([-43, -35, -27, -19, 10, 15, 20, 25]):
        cube(f"接送区车位编号_{i}", (x, -55.0, 0.23), (3.2, 0.08, 0.03), MATS["parking"], 0.004)
    for i, x in enumerate([39.8, 41.6, 43.4, 45.2]):
        cyl(f"共享单车停车架_{i}", (x, -52.8, 0.45), 0.08, 1.2, MATS["metal"], vertices=12, rot=(math.radians(90), 0, 0))

    route_specs = [
        ("步行优先流线", 0, -55.0, 0, -21.0, MATS["white"], 0.22),
        ("家长接送流线", 30, -55.0, 6, -50.5, MATS["orange"], 0.22),
        ("校车运行流线", -47, -55.0, -18, -52.0, MATS["yellow"], 0.24),
        ("自行车骑行流线", 42, -54.5, 35, -15.0, MATS["green"], 0.18),
        ("后勤车辆分流线", -72, 34.0, 67, 34.0, MATS["blue"], 0.2),
        ("无障碍到达流线", 9.5, -50.0, 12.0, 32.0, MATS["white"], 0.26),
    ]
    for name, x1, y1, x2, y2, material, width in route_specs:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, 0.42), (length, width, 0.06), material, 0.006, rot_z=angle)
        cyl(f"{name}_方向箭头", (x2, y2, 0.48), 0.38, 0.08, material, vertices=3, rot=(0, 0, angle - math.pi / 2))

    accessibility_nodes = [
        ("无障碍电梯入口_图书馆", 7.8, -20.8, MATS["screen"]),
        ("无障碍电梯入口_教学楼", -18.0, 15.5, MATS["screen"]),
        ("无障碍电梯入口_体育馆", 43.5, 12.0, MATS["screen"]),
        ("无障碍卫生间_入口", 7.0, -47.5, MATS["white"]),
        ("盲道节点_校门", 0, -50.2, MATS["yellow"]),
        ("盲道节点_图书馆", 0, -22.0, MATS["yellow"]),
        ("盲道节点_医务中心", 12, 31.0, MATS["yellow"]),
    ]
    for name, x, y, material in accessibility_nodes:
        cube(name, (x, y, 0.92), (1.2, 0.7, 1.15), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.35), (0.7, 0.7, 0.42), MATS["orange"], 0.025)

    traffic_ops = [
        ("交通诱导屏_南门", -6, -56.2, MATS["screen"]),
        ("交通诱导屏_西门", -71.8, 34, MATS["screen"]),
        ("交通诱导屏_东应急门", 71.5, -33, MATS["screen"]),
        ("停车余位显示屏", -54, -47.5, MATS["screen"]),
        ("交通流量检测器", 31, -55.2, MATS["screen"]),
        ("违停抓拍摄像机", 21, -55.2, MATS["white"]),
        ("后勤车辆预约终端", 61.5, 34, MATS["screen"]),
        ("应急车辆集结位", 58, -47.0, MATS["red"]),
    ]
    for name, x, y, material in traffic_ops:
        cube(name, (x, y, 1.18), (0.92, 0.42, 1.5), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.4), (0.72, 0.72, 0.42), MATS["orange"], 0.025)

    cube("交通到达无障碍总览牌", (18, -59.0, 1.35), (34, 0.38, 1.9), MATS["panel"], 0.06)
    text("交通到达无障碍总览牌_文字", "交通到达：步行/校车/家长接送/骑行/后勤/消防分流与无障碍连续路径", (18, -59.25, 1.42), 0.32, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_交通到达无障碍运营", (18, -59.0, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_mep_utility_operations():
    # MEP utility network: show how the central gallery feeds buildings with power, fiber, water, HVAC, drainage, and gas.
    utility_routes = [
        ("电力馈线_配电到教学区", -57, -9, -8, 7, MATS["yellow"], 0.18),
        ("电力馈线_配电到生活区", -57, -9, 35, 22, MATS["yellow"], 0.18),
        ("光纤环网_科技楼到教学区", -36, -7, -8, 7, MATS["blue"], 0.16),
        ("光纤环网_科技楼到生活区", -36, -7, 35, 22, MATS["blue"], 0.16),
        ("消防水管_泵房到教学区", -69, 31, -8, 7, MATS["red"], 0.16),
        ("消防水管_泵房到体育区", -69, 31, 55, 11, MATS["red"], 0.16),
        ("生活给水管_水泵房到宿舍", -54, 31, 54, 31, MATS["water"], 0.16),
        ("冷冻水管_能源站到教学区", -59, 35.5, -8, 7, MATS["white"], 0.16),
        ("冷冻水管_能源站到体育馆", -59, 35.5, 55, 11, MATS["white"], 0.16),
        ("雨水回用管_水罐到花园", -72, 39, -14, 38.5, MATS["green"], 0.14),
        ("污水排水管_生活区到处理", 54, 31, -66.5, 45.5, MATS["metal"], 0.14),
        ("食堂燃气管线_调压到后厨", 68, 38, 34, 36.4, MATS["orange"], 0.14),
    ]
    for name, x1, y1, x2, y2, material, width in utility_routes:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, -0.05), (length, width, 0.08), material, 0.006, rot_z=angle)
        cyl(f"{name}_检修节点", (x2, y2, 0.08), 0.34, 0.1, material, vertices=24)

    riser_nodes = [
        ("强电竖井_T01", -38, 4, MATS["yellow"]),
        ("弱电竖井_T01", -36.8, 4, MATS["blue"]),
        ("给排水竖井_T01", -35.6, 4, MATS["water"]),
        ("强电竖井_T02", -12, 12, MATS["yellow"]),
        ("弱电竖井_T02", -10.8, 12, MATS["blue"]),
        ("给排水竖井_T02", -9.6, 12, MATS["water"]),
        ("强电竖井_T03", 14, 12, MATS["yellow"]),
        ("弱电竖井_T03", 15.2, 12, MATS["blue"]),
        ("给排水竖井_T03", 16.4, 12, MATS["water"]),
        ("强电竖井_生活区", 54, 31, MATS["yellow"]),
        ("弱电竖井_生活区", 55.2, 31, MATS["blue"]),
        ("给排水竖井_生活区", 56.4, 31, MATS["water"]),
    ]
    for name, x, y, material in riser_nodes:
        cube(name, (x, y, 4.2), (0.48, 0.48, 2.6), material, 0.025)
        cube(f"设施索引_{name}", (x, y, 5.7), (0.52, 0.52, 0.28), MATS["orange"], 0.018)

    roof_equipment = [
        ("屋顶新风机组_图书馆", 0, -21, MATS["white"]),
        ("屋顶新风机组_STEM", -23, -24, MATS["white"]),
        ("屋顶新风机组_博雅", 23, -24, MATS["white"]),
        ("屋顶新风机组_体育馆", 55, 11, MATS["white"]),
        ("屋顶排烟风机_食堂", 30, 31, MATS["metal"]),
        ("厨房油烟排风井", 38, 36.8, MATS["metal"]),
        ("屋顶水箱_宿舍", 62, 31, MATS["water"]),
        ("屋顶消防稳压罐", 52, 31, MATS["red"]),
        ("电梯机房_教学楼", -12, 12, MATS["metal"]),
        ("电梯机房_生活区", 54, 31, MATS["metal"]),
    ]
    for name, x, y, material in roof_equipment:
        cube(name, (x, y, 8.45 if x in [55, 54, 62, 52] else 6.55), (2.1, 1.25, 0.7), material, 0.045)
        cube(f"设施索引_{name}", (x, y, 8.95 if x in [55, 54, 62, 52] else 7.05), (0.58, 0.58, 0.3), MATS["orange"], 0.02)

    control_nodes = [
        ("BMS楼控传感器_教学区", -8, 7, MATS["screen"]),
        ("BMS楼控传感器_生活区", 35, 22, MATS["screen"]),
        ("BMS楼控传感器_体育区", 55, 11, MATS["screen"]),
        ("管廊环境传感器_温湿度", -18, -11.5, MATS["screen"]),
        ("管廊环境传感器_水浸", 0, -11.5, MATS["screen"]),
        ("管廊环境传感器_可燃气", 35, -11.5, MATS["screen"]),
        ("管廊排水泵坑", 24, -11.5, MATS["water"]),
        ("管廊通风井", -30, -11.5, MATS["metal"]),
    ]
    for name, x, y, material in control_nodes:
        cube(name, (x, y, 0.95), (1.1, 0.72, 1.05), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.34), (0.68, 0.68, 0.4), MATS["orange"], 0.025)

    cube("机电管线楼宇运维总览牌", (-18, -15.6, 1.35), (32, 0.38, 1.9), MATS["panel"], 0.06)
    text("机电管线楼宇运维总览牌_文字", "机电运维：电力/光纤/消防水/生活水/冷冻水/雨污排/燃气/屋顶机电/BMS", (-18, -15.85, 1.42), 0.31, MATS["white"], rot=(math.radians(90), 0, 0))
    cube("设施索引_机电管线楼宇运维", (-18, -15.6, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_campus_governance_operations():
    # Campus governance layer: visible daily operation systems for schedule, service, duty, and data dispatch.
    ops_center = (-31.5, -4.6)
    cube("校园综合运营中心", (ops_center[0], ops_center[1], 1.0), (7.2, 4.4, 2.0), MATS["panel"], 0.12)
    cube("校务数据中台大屏", (ops_center[0], ops_center[1] - 2.23, 1.45), (5.8, 0.12, 1.25), MATS["screen"], 0.035)
    text(
        "校务数据中台大屏_文字",
        "校务运行：课表/考务/值班/报修/访客/宿舍/食堂/场馆",
        (ops_center[0], ops_center[1] - 2.31, 1.55),
        0.23,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("校园运行日报屏", (ops_center[0] - 2.7, ops_center[1] - 0.4, 1.55), (1.0, 0.18, 1.1), MATS["screen"], 0.03)
    cube("值班排班看板", (ops_center[0] - 1.35, ops_center[1] - 0.4, 1.55), (1.0, 0.18, 1.1), MATS["screen"], 0.03)
    cube("资产报修工单屏", (ops_center[0], ops_center[1] - 0.4, 1.55), (1.0, 0.18, 1.1), MATS["screen"], 0.03)
    cube("校园广播分区矩阵", (ops_center[0] + 1.35, ops_center[1] - 0.4, 1.55), (1.0, 0.18, 1.1), MATS["screen"], 0.03)
    cube("移动巡检PDA充电柜", (ops_center[0] + 2.7, ops_center[1] - 0.4, 0.95), (1.0, 0.36, 0.8), MATS["metal"], 0.035)

    schedule_nodes = [
        ("课表铃声控制器", -15, 4.2, MATS["yellow"]),
        ("电子校历活动看板", -4, -34.5, MATS["screen"]),
        ("班级课表同步屏_T01", -39, 7.7, MATS["screen"]),
        ("班级课表同步屏_T02", -12, 15.7, MATS["screen"]),
        ("班级课表同步屏_T03", 15, 15.7, MATS["screen"]),
        ("教务排课服务器", -36, -20.2, MATS["blue"]),
        ("考试考务保密室", -4.8, -21.5, MATS["panel"]),
        ("试卷流转保险柜", -2.8, -21.5, MATS["metal"]),
        ("成绩与学情分析屏", 1.2, -21.5, MATS["screen"]),
    ]
    service_nodes = [
        ("访客预约二维码闸机", -3.5, -52.8, MATS["screen"]),
        ("车辆预约白名单终端", 9.5, -52.3, MATS["screen"]),
        ("校园一卡通充值终端", -8.5, -49.5, MATS["screen"]),
        ("校内导航触摸屏", 4.5, -49.5, MATS["screen"]),
        ("家校通知发布屏", -18, -53.0, MATS["screen"]),
        ("晨检午检健康上报终端", -22.5, 8.4, MATS["green"]),
        ("实验室预约与危化品审批屏", -24.5, -16.8, MATS["screen"]),
        ("体育场地预约屏", 52, 5.4, MATS["screen"]),
        ("食堂错峰就餐调度屏", 28, 24.6, MATS["screen"]),
        ("宿舍晚归点名终端", 48.5, 24.6, MATS["screen"]),
        ("会议室预约门牌_行政", 4.5, -19.0, MATS["screen"]),
        ("师生服务中心窗口", -9.8, -21.5, MATS["stone"]),
    ]
    all_nodes = schedule_nodes + service_nodes
    for name, x, y, material in all_nodes:
        cube(name, (x, y, 1.2), (1.35, 0.7, 1.25), material, 0.045)
        cube(f"设施索引_{name}", (x, y, 0.35), (0.58, 0.58, 0.34), MATS["orange"], 0.02)

    route_targets = [
        ("校务数据总线_到教学区", ops_center[0], ops_center[1], -12, 12, MATS["blue"]),
        ("校务数据总线_到入口服务", ops_center[0], ops_center[1], -3.5, -52.8, MATS["blue"]),
        ("校务数据总线_到食堂", ops_center[0], ops_center[1], 28, 24.6, MATS["blue"]),
        ("校务数据总线_到宿舍", ops_center[0], ops_center[1], 48.5, 24.6, MATS["blue"]),
        ("校务数据总线_到体育馆", ops_center[0], ops_center[1], 52, 5.4, MATS["blue"]),
        ("校务数据总线_到实验室", ops_center[0], ops_center[1], -24.5, -16.8, MATS["blue"]),
        ("校务数据总线_到行政考务", ops_center[0], ops_center[1], -4.8, -21.5, MATS["blue"]),
    ]
    for name, x1, y1, x2, y2, material in route_targets:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, 0.12), (length, 0.13, 0.07), material, 0.006, rot_z=angle)

    duty_points = [
        ("行政值班巡检点", -5, -18),
        ("教学楼值班巡检点", -12, 12),
        ("食堂值班巡检点", 30, 31),
        ("宿舍值班巡检点", 54, 31),
        ("体育馆值班巡检点", 55, 11),
        ("校门值班巡检点", -14, -53.2),
    ]
    for i, (name, x, y) in enumerate(duty_points):
        cyl(name, (x, y, 0.6), 0.38, 1.0, MATS["orange"], vertices=18, bevel=True)
        text(f"{name}_编号", f"D{i + 1}", (x, y, 1.18), 0.38, MATS["white"])

    cube("校园治理运行总览牌", (-46, -2.4, 1.35), (18, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "校园治理运行总览牌_文字",
        "治理运营：校历课表、值班巡检、报修工单、预约审批、家校通知、运行日报",
        (-46, -2.65, 1.42),
        0.28,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_校园治理运行中枢", (-46, -2.4, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_language_international_exchange_center():
    # Foreign-language school layer: make the international and multilingual learning identity explicit.
    center = (18.5, -17.8)
    cube("外语国际交流中心", (center[0], center[1], 1.05), (14.5, 7.6, 2.1), MATS["brick"], 0.14)
    cube("外语国际交流中心_暖白石基座", (center[0], center[1], 0.25), (15.0, 8.1, 0.5), MATS["stone"], 0.06)
    cube("外语国际交流中心_玻璃共享大厅", (center[0], center[1] - 3.82, 1.45), (12.0, 0.18, 1.35), MATS["glass"], 0.025)
    cube("世界地图互动屏", (center[0] - 4.8, center[1] - 3.95, 1.45), (2.4, 0.14, 1.15), MATS["screen"], 0.03)
    cube("国际文化展示廊", (center[0], center[1] - 4.05, 1.16), (5.2, 0.16, 0.72), MATS["purple"], 0.025)
    cube("外国语特色学习中心标识", (center[0] + 4.8, center[1] - 3.95, 1.45), (2.4, 0.14, 1.15), MATS["screen"], 0.03)
    text("外国语特色学习中心标识_文字", "Foreign Language Hub", (center[0] + 4.8, center[1] - 4.08, 1.48), 0.26, MATS["white"], rot=(math.radians(90), 0, 0))

    rooms = [
        ("同声传译实验室", 13.0, -20.0, MATS["blue"]),
        ("多语种听说训练舱", 16.6, -20.0, MATS["screen"]),
        ("模拟联合国教室", 20.2, -20.0, MATS["green"]),
        ("国际辩论教室", 23.8, -20.0, MATS["purple"]),
        ("外籍教师办公室", 12.7, -16.0, MATS["white"]),
        ("国际交流办公室", 15.9, -16.0, MATS["stone"]),
        ("海外升学指导中心", 19.1, -16.0, MATS["orange"]),
        ("雅思托福机考室", 22.3, -16.0, MATS["blue"]),
        ("小语种资源库", 25.5, -16.0, MATS["wood"]),
        ("外文原版阅览角", 11.1, -13.2, MATS["wood"]),
        ("姐妹学校视频连线室", 15.0, -13.2, MATS["screen"]),
        ("语言学习AI口语亭", 18.9, -13.2, MATS["screen"]),
        ("跨文化项目工作坊", 22.8, -13.2, MATS["green"]),
        ("英语戏剧排练角", 26.7, -13.2, MATS["purple"]),
        ("外事接待洽谈室", 28.0, -18.4, MATS["stone"]),
        ("交换生服务台", 9.2, -18.4, MATS["white"]),
    ]
    for name, x, y, material in rooms:
        cube(name, (x, y, 1.2), (2.3, 1.45, 1.35), material, 0.045)
        cube(f"设施索引_{name}", (x, y, 0.35), (0.54, 0.54, 0.32), MATS["orange"], 0.018)

    for i, x in enumerate([12.4, 14.4, 16.4, 18.4, 20.4, 22.4, 24.4]):
        cube(f"文化旗帜廊_旗杆_{i}", (x, -22.45, 1.05), (0.08, 0.08, 1.7), MATS["metal"], 0.01)
        cube(f"文化旗帜廊_旗面_{i}", (x + 0.35, -22.45, 1.65), (0.64, 0.05, 0.42), [MATS["red"], MATS["blue"], MATS["green"], MATS["yellow"], MATS["purple"], MATS["white"], MATS["orange"]][i], 0.01)

    activity_nodes = [
        ("国际周展台", 7.8, -23.2, MATS["orange"]),
        ("外语角交流桌", 10.6, -23.2, MATS["wood"]),
        ("跨文化圆桌区", 27.0, -23.2, MATS["wood"]),
        ("外语演讲小舞台", 30.0, -23.2, MATS["purple"]),
    ]
    for name, x, y, material in activity_nodes:
        cube(name, (x, y, 0.55), (2.1, 1.3, 0.8), material, 0.05)
        cube(f"设施索引_{name}", (x, y, 1.08), (0.5, 0.5, 0.3), MATS["orange"], 0.016)

    flows = [
        ("国际课程走班流线_到国际部", center[0], center[1], 14, 12, MATS["blue"]),
        ("国际课程走班流线_到图书馆", center[0], center[1], 0, -21, MATS["blue"]),
        ("国际课程走班流线_到STEM", center[0], center[1], -23, -24, MATS["blue"]),
        ("国际课程走班流线_到艺术社团", center[0], center[1], 12, -27, MATS["blue"]),
    ]
    for name, x1, y1, x2, y2, material in flows:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, 0.16), (length, 0.16, 0.08), material, 0.006, rot_z=angle)

    cube("外语国际交流总览牌", (19, -11.2, 1.35), (17.5, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "外语国际交流总览牌_文字",
        "外语特色：同传/多语种/模联/辩论/国际交流/升学指导/机考/文化展示",
        (19, -11.45, 1.42),
        0.28,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_外语国际交流学习中心", (19, -11.2, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_surrounding_city_interface():
    # Campus-to-city layer: complete the map with roads, transit, crossings, municipal handoff, and Fangshan context.
    cube("校外城市主干路", (0, -64.0, 0.03), (156, 7.2, 0.06), MATS["road"], 0.03)
    cube("校外慢行绿道", (0, -59.8, 0.08), (148, 2.0, 0.08), MATS["green"], 0.035)
    cube("校外人行道_南侧", (0, -68.2, 0.08), (148, 2.2, 0.08), MATS["paving"], 0.035)
    for x in range(-70, 71, 10):
        cube(f"校外道路中心线_{x}", (x, -64.0, 0.12), (4.2, 0.12, 0.025), MATS["parking"], 0.004)
    for i, x in enumerate([-10, -7.6, -5.2, -2.8, -0.4, 2.0, 4.4, 6.8, 9.2]):
        cube(f"南门斑马线_{i}", (x, -60.9, 0.14), (1.35, 4.2, 0.026), MATS["parking"], 0.003)
    cube("行人过街安全岛", (0, -64.0, 0.2), (7.5, 0.9, 0.26), MATS["stone"], 0.04)
    cube("校门外减速带", (0, -62.0, 0.18), (18.0, 0.28, 0.08), MATS["yellow"], 0.01)

    transit_nodes = [
        ("公交站台_南外方山校区站", -28, -68.0, MATS["roof"]),
        ("校车社会车辆分离标识", -42, -60.0, MATS["screen"]),
        ("出租网约车落客区", 28, -68.0, MATS["orange"]),
        ("地铁接驳步行导向牌", 42, -60.0, MATS["screen"]),
        ("非机动车等候区", 54, -60.0, MATS["green"]),
    ]
    for name, x, y, material in transit_nodes:
        cube(name, (x, y, 1.05), (5.4, 1.25, 1.65), material, 0.06)
        cube(f"设施索引_{name}", (x, y, 0.35), (0.65, 0.65, 0.36), MATS["orange"], 0.02)
    for i, x in enumerate([-31.5, -28, -24.5]):
        cube(f"公交候车座椅_{i}", (x, -67.15, 0.55), (1.2, 0.34, 0.42), MATS["metal"], 0.025)
    for i, x in enumerate([26, 29.5, 33]):
        cube(f"网约车临停位_{i}", (x, -63.8, 0.16), (4.2, 1.7, 0.028), MATS["parking"], 0.004)

    signal_nodes = [
        ("校门交通信号灯_西", -12.5, -61.0, MATS["metal"]),
        ("校门交通信号灯_东", 12.5, -61.0, MATS["metal"]),
        ("学生过街按钮_西", -13.8, -59.4, MATS["yellow"]),
        ("学生过街按钮_东", 13.8, -59.4, MATS["yellow"]),
        ("校外违停抓拍摄像机", 20, -61.0, MATS["white"]),
        ("校外交通流量雷达", -20, -61.0, MATS["screen"]),
    ]
    for name, x, y, material in signal_nodes:
        cube(name, (x, y, 1.15), (0.75, 0.42, 1.55), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.36), (0.55, 0.55, 0.32), MATS["orange"], 0.018)

    municipal_nodes = [
        ("市政给水接入口", -67, -58.2, MATS["water"]),
        ("市政电力环网柜", -61, -58.2, MATS["yellow"]),
        ("市政通信光交箱", -55, -58.2, MATS["blue"]),
        ("市政燃气调压箱", 61, -58.2, MATS["orange"]),
        ("市政污水检查井", 67, -58.2, MATS["metal"]),
        ("校外消防取水口", 72, -58.2, MATS["red"]),
    ]
    for name, x, y, material in municipal_nodes:
        cube(name, (x, y, 0.8), (1.35, 0.9, 1.25), material, 0.04)
        cyl(f"{name}_井盖", (x, y + 0.9, 0.17), 0.38, 0.06, material, vertices=24)
        cube(f"设施索引_{name}", (x, y, 1.58), (0.55, 0.55, 0.28), MATS["orange"], 0.018)

    city_handoff_routes = [
        ("市政给水接驳线_入校", -67, -58.2, -54, 31, MATS["water"], 0.13),
        ("市政电力接驳线_入校", -61, -58.2, -57, -9, MATS["yellow"], 0.13),
        ("市政通信接驳线_入校", -55, -58.2, -36, -7, MATS["blue"], 0.13),
        ("市政燃气接驳线_入校", 61, -58.2, 34, 36.4, MATS["orange"], 0.13),
        ("市政污水外排线_出校", 54, 31, 67, -58.2, MATS["metal"], 0.13),
    ]
    for name, x1, y1, x2, y2, material, width in city_handoff_routes:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, -0.09), (length, width, 0.07), material, 0.005, rot_z=angle)

    for i, (x, y, s) in enumerate([(-66, 49, 1.4), (-54, 51, 1.2), (54, 50, 1.35), (66, 48, 1.15)]):
        add_tree(x, y, s, f"方山生态缓冲林_{i}")
    cube("方山背景观景平台", (-54, 45.8, 0.2), (12.0, 2.8, 0.18), MATS["paving"], 0.04)
    cube("方山背景说明牌", (-54, 44.0, 1.15), (7.5, 0.28, 1.55), MATS["panel"], 0.05)
    text("方山背景说明牌_文字", "方山背景：山水校园、红砖院落、城市慢行绿道衔接", (-54, 43.8, 1.22), 0.27, MATS["white"], rot=(math.radians(90), 0, 0))

    cube("校外周边市政界面总览牌", (0, -70.2, 1.35), (36, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "校外周边市政界面总览牌_文字",
        "校外界面：城市道路/公交站/过街安全/慢行绿道/市政水电气通信/方山生态背景",
        (0, -70.45, 1.42),
        0.31,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_校外周边市政界面", (0, -70.2, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_night_weather_resilience_operations():
    # Campus night/weather operations: lighting, drainage, lightning protection, and extreme-weather response.
    lighting_points = [
        ("智慧路灯_南门广场_西", -18, -50.2),
        ("智慧路灯_南门广场_东", 18, -50.2),
        ("智慧路灯_主轴_01", 0, -36),
        ("智慧路灯_主轴_02", 0, -22),
        ("智慧路灯_主轴_03", 0, -8),
        ("智慧路灯_主轴_04", 0, 8),
        ("智慧路灯_主轴_05", 0, 24),
        ("智慧路灯_生活区", 46, 28),
        ("智慧路灯_后勤区", 66, 36),
        ("智慧路灯_校外公交站", -28, -66.5),
    ]
    for i, (name, x, y) in enumerate(lighting_points):
        cyl(name, (x, y, 2.1), 0.07, 4.2, MATS["metal"], vertices=12)
        cube(f"{name}_LED双臂灯头", (x, y + 0.38, 4.18), (0.85, 0.22, 0.18), MATS["light"], 0.025)
        cube(f"设施索引_{name}", (x, y, 0.32), (0.55, 0.55, 0.32), MATS["orange"], 0.018)
        if i in [0, 1, 3, 5, 9]:
            bpy.ops.object.light_add(type="POINT", location=(x, y, 4.0))
            lamp = bpy.context.object
            lamp.name = f"{name}_真实点光源"
            lamp.data.energy = 55
            lamp.data.shadow_soft_size = 4.5

    bollards = [(-28, -39), (-18, -34), (-8, -29), (8, -25), (18, -22), (28, -18), (38, -14), (48, -9)]
    for i, (x, y) in enumerate(bollards):
        cyl(f"低位庭院灯_{i}", (x, y, 0.55), 0.13, 1.1, MATS["light"], vertices=16, bevel=True)

    floodlights = [
        ("操场泛光灯塔_西南", 24, -42, 7.2),
        ("操场泛光灯塔_东南", 66, -42, 7.2),
        ("操场泛光灯塔_西北", 24, -14, 7.2),
        ("操场泛光灯塔_东北", 66, -14, 7.2),
        ("体育馆立面洗墙灯", 55, 4, 6.8),
        ("图书馆立面洗墙灯", 0, -27, 5.4),
    ]
    for name, x, y, z in floodlights:
        cyl(name, (x, y, z / 2), 0.1, z, MATS["metal"], vertices=12)
        cube(f"{name}_灯组", (x, y + 0.42, z), (1.1, 0.32, 0.32), MATS["light"], 0.03)
        cube(f"设施索引_{name}", (x, y, 0.42), (0.62, 0.62, 0.34), MATS["orange"], 0.02)

    dorm_windows = [(45, 27.5), (49, 27.5), (53, 27.5), (57, 27.5), (61, 27.5), (45, 34.5), (49, 34.5), (53, 34.5), (57, 34.5), (61, 34.5)]
    for i, (x, y) in enumerate(dorm_windows):
        cube(f"宿舍夜间暖光窗_{i}", (x, y, 5.15), (1.4, 0.08, 0.45), MATS["light"], 0.01)
    cube("宿舍夜间查寝屏", (48.5, 26.2, 1.35), (2.4, 0.14, 1.0), MATS["screen"], 0.03)
    cube("宿舍夜间静音提示牌", (56.5, 26.2, 1.25), (2.1, 0.14, 0.85), MATS["panel"], 0.03)

    drainage_points = [
        ("雨水篦子_南门低点", -8, -51.5),
        ("雨水篦子_主轴低点", 0, -12),
        ("雨水篦子_食堂后场", 37, 39),
        ("雨水篦子_操场南侧", 45, -43),
        ("雨水篦子_公交站", -30, -68),
        ("积水监测传感器_南门", 8, -51.5),
        ("积水监测传感器_操场", 55, -42),
        ("积水监测传感器_后勤", 64, 39),
    ]
    for name, x, y in drainage_points:
        cube(name, (x, y, 0.18), (1.15, 0.5, 0.08), MATS["metal"], 0.015)
        cube(f"设施索引_{name}", (x, y, 0.48), (0.5, 0.5, 0.28), MATS["orange"], 0.016)
    cube("暴雨溢流导排线_南门到雨水花园", (-27, -7.0, 0.1), (92, 0.16, 0.06), MATS["water"], 0.005, rot_z=math.radians(74))
    cube("暴雨溢流导排线_操场到雨水花园", (3.5, -0.5, 0.1), (91, 0.16, 0.06), MATS["water"], 0.005, rot_z=math.radians(126))

    weather_nodes = [
        ("屋顶防雷针_图书馆", 0, -21, 7.2),
        ("屋顶防雷针_STEM", -23, -24, 6.8),
        ("屋顶防雷针_体育馆", 55, 11, 9.0),
        ("屋顶防雷针_宿舍", 54, 31, 9.0),
    ]
    for name, x, y, z in weather_nodes:
        cyl(name, (x, y, z), 0.045, 1.6, MATS["metal"], vertices=10)
        cube(f"设施索引_{name}", (x, y, z + 0.95), (0.48, 0.48, 0.25), MATS["orange"], 0.014)
    cube("雷暴天气预警屏", (-4, -49.5, 1.35), (2.8, 0.16, 1.15), MATS["screen"], 0.03)
    cube("高温避暑开放点_图书馆", (5.5, -24.5, 1.0), (2.4, 1.3, 1.2), MATS["water"], 0.04)
    cube("雨雪防滑物资箱_南门", (-10.5, -50.5, 0.7), (1.6, 0.8, 0.9), MATS["yellow"], 0.035)
    cube("极端天气停课联动屏", (-31.5, -2.2, 1.35), (2.5, 0.16, 1.0), MATS["screen"], 0.03)

    control_routes = [
        ("夜间照明控制回路_主轴", 0, -50, 0, 26, MATS["yellow"], 0.11),
        ("夜间照明控制回路_操场", 0, -8, 55, -28, MATS["yellow"], 0.11),
        ("天气告警数据线_气象站到总控", -18, 38.5, -31.5, -4.6, MATS["blue"], 0.11),
        ("积水告警数据线_南门到总控", 8, -51.5, -31.5, -4.6, MATS["blue"], 0.11),
    ]
    for name, x1, y1, x2, y2, material, width in control_routes:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, 0.24), (length, width, 0.06), material, 0.005, rot_z=angle)

    cube("夜间天气韧性运行总览牌", (-32, -47.8, 1.35), (28, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "夜间天气韧性运行总览牌_文字",
        "夜间天气：智慧路灯/庭院灯/泛光照明/暖光窗/排水篦子/积水监测/防雷/雷暴高温雨雪联动",
        (-32, -48.05, 1.42),
        0.28,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_夜间天气韧性运行", (-32, -47.8, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_wireless_edge_network_operations():
    # Wireless and edge-computing layer: show daily digital infrastructure beyond the backbone fiber.
    ap_points = [
        ("无线AP_图书馆阅览", -4, -20.6),
        ("无线AP_STEM实验", -23, -24),
        ("无线AP_初中组团", -38, 4),
        ("无线AP_高中组团", -12, 12),
        ("无线AP_国际部组团", 14, 12),
        ("无线AP_共享教室", 40, 4),
        ("无线AP_体育馆", 55, 11),
        ("无线AP_食堂", 30, 31),
        ("无线AP_宿舍", 54, 31),
        ("无线AP_操场看台", 45, -40),
        ("无线AP_校门广场", 0, -50),
        ("无线AP_外语中心", 18, -18),
    ]
    for name, x, y in ap_points:
        cyl(name, (x, y, 5.4 if y > -5 else 3.8), 0.28, 0.12, MATS["white"], vertices=24, bevel=True)
        cyl(f"{name}_覆盖圈", (x, y, 0.16), 3.6, 0.035, MATS["glass"], vertices=48)
        cube(f"设施索引_{name}", (x, y, 0.48), (0.52, 0.52, 0.28), MATS["orange"], 0.016)

    edge_nodes = [
        ("边缘计算盒_教学区", -12, 6, MATS["panel"]),
        ("边缘计算盒_体育区", 55, 4, MATS["panel"]),
        ("边缘计算盒_生活区", 54, 25, MATS["panel"]),
        ("边缘计算盒_入口区", -4, -50, MATS["panel"]),
        ("物联网网关_能耗水务", -62, 31, MATS["blue"]),
        ("物联网网关_安防消防", -36, -5, MATS["blue"]),
        ("物联网网关_环境健康", -18, 38, MATS["blue"]),
        ("物联网网关_交通到达", 16, -55, MATS["blue"]),
    ]
    for name, x, y, material in edge_nodes:
        cube(name, (x, y, 1.1), (1.2, 0.8, 1.05), material, 0.04)
        cube(f"{name}_状态灯", (x, y - 0.43, 1.34), (0.72, 0.06, 0.22), MATS["screen"], 0.012)
        cube(f"设施索引_{name}", (x, y, 0.34), (0.58, 0.58, 0.32), MATS["orange"], 0.018)

    cyber_nodes = [
        ("校园核心交换机", -37.8, -21.3, MATS["blue"]),
        ("下一代防火墙", -35.8, -21.3, MATS["red"]),
        ("网络准入NAC控制器", -33.8, -21.3, MATS["panel"]),
        ("日志审计与安全态势屏", -31.8, -21.3, MATS["screen"]),
        ("备份容灾一体机", -29.8, -21.3, MATS["metal"]),
    ]
    for name, x, y, material in cyber_nodes:
        cube(name, (x, y, 2.62), (1.45, 0.8, 0.48), material, 0.03)
        cube(f"设施索引_{name}", (x, y, 3.05), (0.46, 0.46, 0.24), MATS["orange"], 0.014)

    clock_broadcast = [
        ("NTP时钟服务器", -36.5, -19.2, MATS["screen"]),
        ("校园统一时钟屏_入口", -2, -49.0, MATS["screen"]),
        ("校园统一时钟屏_教学楼", -12, 16.6, MATS["screen"]),
        ("校园统一时钟屏_体育馆", 50, 4.8, MATS["screen"]),
        ("IP广播分区终端_教学区", -18, 9, MATS["white"]),
        ("IP广播分区终端_操场", 44, -33, MATS["white"]),
        ("IP广播分区终端_宿舍", 52, 25, MATS["white"]),
    ]
    for name, x, y, material in clock_broadcast:
        cube(name, (x, y, 1.4), (1.15, 0.42, 0.92), material, 0.035)
        cube(f"设施索引_{name}", (x, y, 0.42), (0.55, 0.55, 0.3), MATS["orange"], 0.016)

    wireless_routes = [
        ("无线控制器到教学AP链路", -36, -22, -12, 12, MATS["blue"], 0.1),
        ("无线控制器到体育AP链路", -36, -22, 55, 11, MATS["blue"], 0.1),
        ("无线控制器到宿舍AP链路", -36, -22, 54, 31, MATS["blue"], 0.1),
        ("无线控制器到校门AP链路", -36, -22, 0, -50, MATS["blue"], 0.1),
        ("IoT传感器汇聚链路_环境", -18, 38, -31.5, -4.6, MATS["green"], 0.1),
        ("IoT传感器汇聚链路_能耗", -62, 31, -31.5, -4.6, MATS["green"], 0.1),
        ("安全日志回传链路", -36, -7, -31.8, -21.3, MATS["red"], 0.1),
    ]
    for name, x1, y1, x2, y2, material, width in wireless_routes:
        angle = math.atan2(y2 - y1, x2 - x1)
        length = math.hypot(x2 - x1, y2 - y1)
        cube(name, ((x1 + x2) / 2, (y1 + y2) / 2, 0.28), (length, width, 0.06), material, 0.005, rot_z=angle)

    cube("无线网络边缘计算总览牌", (-48, -15.2, 1.35), (25, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "无线网络边缘计算总览牌_文字",
        "数字底座：无线AP覆盖/边缘计算/IoT网关/防火墙/NAC/日志审计/NTP/IP广播",
        (-48, -15.45, 1.42),
        0.29,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_无线网络边缘计算", (-48, -15.2, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_complete_building_interiors():
    # Requirement layer: every major building in the map receives a visible interior program, not just an exterior mass.
    def room(name, x, y, z, w, d, material, label_size=0.22):
        cube(name, (x, y, z), (w, d, 0.14), material, 0.025)
        cube(f"{name}_家具设备", (x, y, z + 0.22), (w * 0.55, d * 0.18, 0.18), MATS["wood"], 0.012)
        text(f"{name}_标签", name.replace("完整室内_", ""), (x, y, z + 0.48), label_size, MATS["white"])

    building_specs = [
        ("保安室", -14, -53.2, 3.28, [("值班桌", -15.4, -53.8, MATS["wood"]), ("访客登记", -14, -53.8, MATS["screen"]), ("警械装备柜", -12.6, -53.8, MATS["metal"]), ("快递暂存", -14, -52.1, MATS["stone"])]),
        ("图书馆行政中心", 0, -21, 7.25, [("总服务台", -4.8, -22.8, MATS["wood"]), ("外文书库", -1.6, -22.8, MATS["blue"]), ("自习舱", 1.6, -22.8, MATS["white"]), ("行政会议室", 4.8, -22.8, MATS["green"])]),
        ("STEM中心", -23, -24, 6.65, [("物理准备室", -26.9, -25.8, MATS["blue"]), ("化学准备室", -24.3, -25.8, MATS["green"]), ("生物准备室", -21.7, -25.8, MATS["purple"]), ("创客工具墙", -19.1, -25.8, MATS["orange"])]),
        ("博雅中心", 23, -24, 6.65, [("语言教研室", 19.1, -25.8, MATS["blue"]), ("录播教室", 21.7, -25.8, MATS["screen"]), ("报告厅后台", 24.3, -25.8, MATS["metal"]), ("艺术讨论室", 26.9, -25.8, MATS["purple"])]),
        ("初中教学组团", -38, 4, 6.35, [("班级教室", -42.6, 2.1, MATS["white"]), ("教师办公室", -39.4, 2.1, MATS["wood"]), ("年级活动角", -36.2, 2.1, MATS["green"]), ("卫生间茶水", -33.0, 2.1, MATS["water"])]),
        ("高中教学组团", -12, 12, 6.35, [("选科教室", -16.6, 10.1, MATS["white"]), ("导师答疑室", -13.4, 10.1, MATS["wood"]), ("竞赛讨论室", -10.2, 10.1, MATS["purple"]), ("学科资料间", -7.0, 10.1, MATS["stone"])]),
        ("国际部教学组团", 14, 12, 6.35, [("国际课程教室", 9.4, 10.1, MATS["white"]), ("外教备课室", 12.6, 10.1, MATS["wood"]), ("申请辅导室", 15.8, 10.1, MATS["screen"]), ("跨文化讨论区", 19.0, 10.1, MATS["green"])]),
        ("小学共享教室组团", 40, 4, 6.35, [("共享教室", 35.4, 2.1, MATS["white"]), ("阅读角", 38.6, 2.1, MATS["wood"]), ("项目学习区", 41.8, 2.1, MATS["green"]), ("教师看护点", 45.0, 2.1, MATS["stone"])]),
        ("科技运维楼", -48, -21, 5.55, [("冷通道机柜", -54.8, -20.0, MATS["panel"]), ("网络运维席", -51.6, -20.0, MATS["screen"]), ("UPS电池间", -48.4, -20.0, MATS["yellow"]), ("备件库", -45.2, -20.0, MATS["metal"])]),
        ("室内体育馆", 55, 11, 8.85, [("器材库", 49.8, 8.0, MATS["metal"]), ("男女更衣", 53.2, 8.0, MATS["white"]), ("赛事控制室", 56.6, 8.0, MATS["screen"]), ("医务裁判室", 60.0, 8.0, MATS["red"])]),
        ("食堂", 30, 31, 5.65, [("学生餐厅", 24.6, 29.5, MATS["wood"]), ("教工餐厅", 28.2, 29.5, MATS["stone"]), ("明厨亮灶", 31.8, 29.5, MATS["screen"]), ("洗消回收", 35.4, 29.5, MATS["green"])]),
        ("宿舍生活组团", 54, 31, 7.35, [("宿舍房间", 48.6, 30.0, MATS["white"]), ("公共自习", 52.2, 30.0, MATS["wood"]), ("洗衣淋浴", 55.8, 30.0, MATS["water"]), ("宿管值班", 59.4, 30.0, MATS["screen"])]),
        ("医务心理中心", 12, 32, 4.75, [("诊室", 8.8, 30.6, MATS["white"]), ("观察室", 11.0, 30.6, MATS["water"]), ("心理沙盘室", 13.2, 30.6, MATS["wood"]), ("团辅室", 15.4, 30.6, MATS["green"])]),
        ("外语国际交流中心", 18.5, -17.8, 3.25, [("同传控制间", 14.0, -18.9, MATS["screen"]), ("模联圆桌", 17.0, -18.9, MATS["green"]), ("外事接待", 20.0, -18.9, MATS["stone"]), ("机考监考", 23.0, -18.9, MATS["blue"])]),
    ]

    for building_name, cx, cy, z, spaces in building_specs:
        cube(f"完整室内_{building_name}_楼层底图", (cx, cy, z), (9.8, 5.2, 0.08), MATS["glass"], 0.025)
        cube(f"完整室内_{building_name}_主走廊", (cx, cy, z + 0.1), (8.6, 0.45, 0.08), MATS["paving"], 0.012)
        for item_name, x, y, material in spaces:
            room(f"完整室内_{building_name}_{item_name}", x, y, z + 0.18, 2.15, 1.25, material)
        cube(f"设施索引_完整室内_{building_name}", (cx, cy, z + 0.72), (0.78, 0.78, 0.32), MATS["orange"], 0.02)

    cube("全建筑室内详图覆盖总览牌", (0, 36.8, 1.35), (42, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "全建筑室内详图覆盖总览牌_文字",
        "室内覆盖：保安/图书行政/STEM/博雅/四组教学/科技运维/体育馆/食堂/宿舍/医务心理/外语中心均含室内功能",
        (0, 36.55, 1.42),
        0.28,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_全建筑室内详图覆盖", (0, 36.8, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_game_main_teaching_building_detail():
    # Main gameplay building: a detailed four-floor teaching block with corridor depth, toilets, stairs, and classroom props.
    cx, cy = -12, 12
    floor_z = [6.9, 8.65, 10.4, 12.15]
    floor_names = ["1F公共大厅", "2F标准教室层", "3F选科教室层", "4F社团备课层"]
    for floor_idx, z in enumerate(floor_z):
        level = floor_idx + 1
        cube(f"游戏主教学楼_{level}F_整层楼板", (cx, cy, z), (18.8, 13.2, 0.12), MATS["stone"], 0.035)
        cube(f"游戏主教学楼_{level}F_宽走廊景深", (cx, cy, z + 0.18), (16.6, 2.15, 0.12), MATS["paving"], 0.025)
        cube(f"游戏主教学楼_{level}F_走廊北侧玻璃栏", (cx, cy + 1.12, z + 0.72), (16.4, 0.08, 0.95), MATS["glass"], 0.015)
        cube(f"游戏主教学楼_{level}F_走廊南侧展板墙", (cx, cy - 1.12, z + 0.72), (16.4, 0.1, 0.95), MATS["panel"], 0.015)
        text(f"游戏主教学楼_{level}F_楼层导视", f"T02 {floor_names[floor_idx]}", (cx - 7.3, cy - 1.22, z + 1.02), 0.24, MATS["light"], rot=(math.radians(90), 0, 0))
        for x in [-18.6, -15.8, -8.2, -5.4]:
            cube(f"游戏主教学楼_{level}F_走廊储物柜_{x}", (x, cy - 0.82, z + 0.52), (0.82, 0.18, 0.72), MATS["metal"], 0.012)
        for x in [-19.5, -4.5]:
            cube(f"游戏主教学楼_{level}F_消防栓_{x}", (x, cy + 0.96, z + 0.55), (0.38, 0.12, 0.56), MATS["red"], 0.012)
            cube(f"游戏主教学楼_{level}F_逃生指示_{x}", (x + 0.55, cy + 0.96, z + 0.95), (0.52, 0.08, 0.22), MATS["light"], 0.008)

        # Vertical circulation cores remain aligned through all floors.
        for stair_name, sx in [("西楼梯", cx - 8.2), ("东楼梯", cx + 8.2)]:
            cube(f"游戏主教学楼_{level}F_{stair_name}_楼梯间", (sx, cy, z + 0.45), (1.55, 2.15, 0.9), MATS["metal"], 0.025)
            for step in range(5):
                cube(f"游戏主教学楼_{level}F_{stair_name}_踏步_{step}", (sx, cy - 0.72 + step * 0.32, z + 0.18 + step * 0.08), (1.25, 0.18, 0.08), MATS["stone"], 0.006)
        cube(f"游戏主教学楼_{level}F_电梯厅", (cx + 6.3, cy, z + 0.48), (1.35, 1.65, 0.95), MATS["metal"], 0.025)
        cube(f"游戏主教学楼_{level}F_电梯门", (cx + 6.3, cy - 0.86, z + 0.55), (0.86, 0.08, 0.75), MATS["screen"], 0.012)

        toilet_x = cx + 7.9
        cube(f"游戏主教学楼_{level}F_厕所景深空间", (toilet_x, cy + 4.05, z + 0.2), (3.0, 2.25, 0.12), MATS["white"], 0.02)
        cube(f"游戏主教学楼_{level}F_男厕隔间区", (toilet_x - 0.78, cy + 4.28, z + 0.52), (1.1, 0.9, 0.56), MATS["blue"], 0.012)
        cube(f"游戏主教学楼_{level}F_女厕隔间区", (toilet_x + 0.78, cy + 4.28, z + 0.52), (1.1, 0.9, 0.56), MATS["purple"], 0.012)
        cube(f"游戏主教学楼_{level}F_无障碍卫生间", (toilet_x, cy + 3.2, z + 0.52), (1.0, 0.72, 0.56), MATS["green"], 0.012)
        for i, ox in enumerate([-1.05, -0.55, 0.55, 1.05]):
            cube(f"游戏主教学楼_{level}F_洗手台_{i}", (toilet_x + ox, cy + 2.75, z + 0.38), (0.42, 0.28, 0.22), MATS["water"], 0.008)
            cube(f"游戏主教学楼_{level}F_镜面_{i}", (toilet_x + ox, cy + 2.58, z + 0.74), (0.38, 0.04, 0.38), MATS["glass"], 0.004)

        room_defs = [
            ("北侧A教室", cx - 5.7, cy + 4.0, MATS["white"]),
            ("北侧B教室", cx - 1.7, cy + 4.0, MATS["white"]),
            ("南侧A教室", cx - 5.7, cy - 4.0, MATS["white"]),
            ("南侧B教室", cx - 1.7, cy - 4.0, MATS["white"]),
        ]
        if level == 1:
            room_defs = [("门厅接待", cx - 5.7, cy + 4.0, MATS["stone"]), ("学生储物大厅", cx - 1.7, cy + 4.0, MATS["metal"]), ("年级公告厅", cx - 5.7, cy - 4.0, MATS["screen"]), ("开放讨论区", cx - 1.7, cy - 4.0, MATS["wood"])]
        elif level == 3:
            room_defs = [("物理选科教室", cx - 5.7, cy + 4.0, MATS["blue"]), ("历史选科教室", cx - 1.7, cy + 4.0, MATS["wood"]), ("导师办公室", cx - 5.7, cy - 4.0, MATS["green"]), ("学科讨论室", cx - 1.7, cy - 4.0, MATS["purple"])]
        elif level == 4:
            room_defs = [("社团活动教室", cx - 5.7, cy + 4.0, MATS["orange"]), ("备课资料室", cx - 1.7, cy + 4.0, MATS["wood"]), ("小型录播室", cx - 5.7, cy - 4.0, MATS["screen"]), ("屋顶设备检修间", cx - 1.7, cy - 4.0, MATS["metal"])]

        for room_idx, (room_name, rx, ry, material) in enumerate(room_defs):
            cube(f"游戏主教学楼_{level}F_{room_name}_教室详细布景", (rx, ry, z + 0.22), (3.35, 2.3, 0.12), material, 0.02)
            cube(f"游戏主教学楼_{level}F_{room_name}_智慧黑板", (rx, ry + (1.18 if ry < cy else -1.18), z + 0.86), (2.1, 0.08, 0.64), MATS["screen"], 0.01)
            cube(f"游戏主教学楼_{level}F_{room_name}_讲台", (rx, ry + (0.72 if ry < cy else -0.72), z + 0.42), (1.15, 0.38, 0.18), MATS["wood"], 0.01)
            cube(f"游戏主教学楼_{level}F_{room_name}_电子班牌", (rx - 1.85, cy + (1.18 if ry > cy else -1.18), z + 0.82), (0.42, 0.08, 0.28), MATS["screen"], 0.006)
            for row in range(3):
                for col in range(3):
                    cube(f"游戏主教学楼_{level}F_{room_name}_课桌椅_{row}_{col}", (rx - 0.9 + col * 0.9, ry - 0.45 + row * 0.42, z + 0.42), (0.48, 0.28, 0.16), MATS["wood"], 0.008)
            for wx in [-1.35, 0, 1.35]:
                cube(f"游戏主教学楼_{level}F_{room_name}_外窗_{wx}", (rx + wx, ry + (1.22 if ry > cy else -1.22), z + 0.9), (0.72, 0.05, 0.5), MATS["glass"], 0.006)

    cube("游戏主教学楼_四层剖面主场景总览牌", (cx, cy + 8.0, 1.35), (26, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "游戏主教学楼_四层剖面主场景总览牌_文字",
        "主场景教学楼：四层、宽走廊景深、厕所隔间/洗手台、楼梯电梯、教室布景、储物柜、消防与导视",
        (cx, cy + 7.75, 1.42),
        0.28,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_游戏主教学楼_四层详细室内", (cx, cy + 8.0, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


def make_game_navigation_interaction_markers():
    # Game-readiness layer for the main teaching building: spawn points, door markers, route volumes, and quest anchors.
    cx, cy = -12, 12
    floor_z = [7.22, 8.97, 10.72, 12.47]
    for floor_idx, z in enumerate(floor_z):
        level = floor_idx + 1
        route_nodes = [(-19.2, cy, "西楼梯"), (-16.0, cy, "走廊西段"), (-12.0, cy, "走廊中段"), (-8.0, cy, "走廊东段"), (-5.7, cy, "电梯厅")]
        for node_idx, (x, y, label) in enumerate(route_nodes):
            cyl(f"游戏主教学楼_{level}F_可通行导航节点_{label}", (x, y, z + 0.08), 0.22, 0.08, MATS["green"], vertices=24)
            if node_idx:
                prev_x, prev_y, _ = route_nodes[node_idx - 1]
                angle = math.atan2(y - prev_y, x - prev_x)
                length = math.hypot(x - prev_x, y - prev_y)
                cube(f"游戏主教学楼_{level}F_可通行走廊路径_{node_idx}", ((x + prev_x) / 2, (y + prev_y) / 2, z + 0.06), (length, 0.22, 0.06), MATS["green"], 0.004, rot_z=angle)

        door_specs = [
            ("北A门洞", -5.7, cy + 1.22, MATS["yellow"]),
            ("北B门洞", -1.7, cy + 1.22, MATS["yellow"]),
            ("南A门洞", -5.7, cy - 1.22, MATS["yellow"]),
            ("南B门洞", -1.7, cy - 1.22, MATS["yellow"]),
            ("厕所门洞", cx + 7.9, cy + 2.2, MATS["water"]),
            ("西楼梯门洞", cx - 8.2, cy - 1.18, MATS["orange"]),
            ("东楼梯门洞", cx + 8.2, cy - 1.18, MATS["orange"]),
            ("电梯门洞", cx + 6.3, cy - 1.18, MATS["blue"]),
        ]
        for name, x, y, material in door_specs:
            cube(f"游戏主教学楼_{level}F_{name}_交互门洞", (x, y, z + 0.42), (0.82, 0.12, 0.9), material, 0.01)
            cube(f"游戏主教学楼_{level}F_{name}_交互提示牌", (x, y, z + 1.05), (0.58, 0.06, 0.22), MATS["screen"], 0.006)

        boundary_specs = [
            ("北栏杆碰撞边界", cx, cy + 6.62, 0, 18.6),
            ("南栏杆碰撞边界", cx, cy - 6.62, 0, 18.6),
            ("西外墙碰撞边界", cx - 9.4, cy, math.radians(90), 13.0),
            ("东外墙碰撞边界", cx + 9.4, cy, math.radians(90), 13.0),
        ]
        for name, x, y, rot, length in boundary_specs:
            cube(f"游戏主教学楼_{level}F_{name}", (x, y, z + 0.38), (length, 0.08, 0.76), MATS["red"], 0.004, rot_z=rot)

    vertical_links = [
        ("西楼梯垂直连接线", cx - 8.2, cy),
        ("东楼梯垂直连接线", cx + 8.2, cy),
        ("电梯垂直连接线", cx + 6.3, cy),
    ]
    for name, x, y in vertical_links:
        cyl(f"游戏主教学楼_{name}", (x, y, 9.7), 0.12, 5.6, MATS["blue"], vertices=16)

    gameplay_points = [
        ("玩家出生点_一层门厅", cx - 7.0, cy - 0.25, floor_z[0] + 0.25, MATS["green"]),
        ("任务点_领取课表", cx - 5.7, cy + 4.0, floor_z[0] + 0.3, MATS["screen"]),
        ("任务点_寻找储物柜钥匙", cx - 16.0, cy - 0.82, floor_z[1] + 0.3, MATS["orange"]),
        ("任务点_进入二层标准教室", cx - 5.7, cy + 2.0, floor_z[1] + 0.3, MATS["yellow"]),
        ("任务点_三层导师办公室", cx - 5.7, cy - 4.0, floor_z[2] + 0.3, MATS["purple"]),
        ("任务点_四层录播室", cx - 5.7, cy - 4.0, floor_z[3] + 0.3, MATS["screen"]),
        ("存档点_电梯厅", cx + 6.3, cy + 0.65, floor_z[0] + 0.3, MATS["blue"]),
        ("检查点_厕所洗手台", cx + 7.9, cy + 2.75, floor_z[1] + 0.3, MATS["water"]),
    ]
    for name, x, y, z, material in gameplay_points:
        cyl(f"游戏主教学楼_{name}", (x, y, z), 0.32, 0.16, material, vertices=32, bevel=True)
        cube(f"游戏主教学楼_{name}_浮标", (x, y, z + 0.55), (0.42, 0.42, 0.42), material, 0.04)

    cube("游戏主教学楼_导航交互总览牌", (cx - 28, cy + 4, 1.35), (25, 0.38, 1.9), MATS["panel"], 0.06)
    text(
        "游戏主教学楼_导航交互总览牌_文字",
        "游戏可用：出生点/任务点/交互门洞/可通行走廊路径/楼梯电梯垂直连接/碰撞边界/存档检查点",
        (cx - 28, cy + 3.75, 1.42),
        0.28,
        MATS["white"],
        rot=(math.radians(90), 0, 0),
    )
    cube("设施索引_游戏主教学楼_导航交互", (cx - 28, cy + 4, 2.55), (1.0, 1.0, 0.45), MATS["orange"], 0.04)


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
    ("17_智慧安全消防韧性系统", (-82, -62, 25), (-24, -27, 2), 28),
    ("18_低碳生态科学运维", (-88, 72, 28), (-38, 40, 2), 30),
    ("19_文化艺术社团公共学习", (52, -58, 24), (12, -27, 3), 30),
    ("20_交通到达无障碍运营", (40, -80, 23), (5, -50, 2), 28),
    ("21_机电管线楼宇运维", (72, 62, 34), (0, 6, 1), 28),
    ("22_校园治理运行中枢", (-76, -34, 24), (-25, -9, 2), 28),
    ("23_外语国际交流学习中心", (54, -45, 21), (18, -18, 2), 30),
    ("24_校外周边市政界面", (48, -92, 24), (0, -61, 1), 28),
    ("25_夜间天气韧性运行", (62, -74, 25), (6, -32, 2), 28),
    ("26_无线网络边缘计算", (-82, -42, 24), (-30, -14, 2), 28),
    ("27_全建筑室内详图覆盖", (76, 48, 30), (16, 12, 5), 30),
    ("28_游戏主教学楼四层室内", (32, 42, 22), (-12, 12, 9), 34),
    ("29_游戏主教学楼导航交互", (-46, 32, 18), (-12, 12, 8), 40),
    ("30_南外方山公开资料复刻层", (82, -82, 54), (0, -4, 1), 30),
    ("31_南外方山高相似公开细化", (72, 62, 36), (2, 16, 2), 32),
    ("32_南外方山公开课程庭院细节", (68, -68, 34), (2, -8, 3), 32),
]


def render_previews():
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for f in os.listdir(PREVIEW_DIR):
        if f.endswith(".png"):
            os.remove(os.path.join(PREVIEW_DIR, f))
    bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
    bpy.context.scene.display.shading.light = "STUDIO"
    bpy.context.scene.display.shading.color_type = "MATERIAL"
    bpy.context.scene.render.resolution_x = 1100
    bpy.context.scene.render.resolution_y = 720
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
    make_fangshan_public_reference_reconstruction()
    make_fangshan_high_fidelity_public_details()
    make_fangshan_program_courtyard_details()
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
    make_security_fire_resilience_detail()
    make_low_carbon_science_operations()
    make_culture_arts_student_center()
    make_transport_accessibility_operations()
    make_mep_utility_operations()
    make_campus_governance_operations()
    make_language_international_exchange_center()
    make_surrounding_city_interface()
    make_night_weather_resilience_operations()
    make_wireless_edge_network_operations()
    make_complete_building_interiors()
    make_game_main_teaching_building_detail()
    make_game_navigation_interaction_markers()
    make_labels_and_legend()
    setup_camera_lights()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    if not SKIP_PREVIEWS:
        render_previews()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


if __name__ == "__main__":
    build_scene()
