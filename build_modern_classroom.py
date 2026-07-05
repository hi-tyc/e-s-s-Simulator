import math
import os

import bpy
from mathutils import Vector


ROOT = os.environ.get("CLASSROOM_ROOT", os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.environ.get("CLASSROOM_BLEND", os.path.join(ROOT, "classroom.blend"))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


def material(name, color, roughness=0.55, metallic=0.0, alpha=1.0, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Alpha"].default_value = alpha
        if emission:
            bsdf.inputs["Emission Color"].default_value = emission
            bsdf.inputs["Emission Strength"].default_value = strength
        bsdf.inputs["Base Color"].default_value = color
    mat.diffuse_color = color
    if alpha < 1:
        mat.blend_method = "BLEND"
        mat.use_screen_refraction = True
        mat.show_transparent_back = True
    return mat


MATS = {}


def init_materials():
    MATS.update(
        {
            "floor": material("warm grey oak floor", (0.62, 0.55, 0.46, 1), 0.42),
            "floor_alt": material("subtle floor plank variation", (0.53, 0.49, 0.42, 1), 0.48),
            "wall": material("soft warm white wall", (0.89, 0.90, 0.88, 1), 0.72),
            "ceiling": material("clean white acoustic ceiling", (0.78, 0.78, 0.74, 1), 0.7),
            "accent": material("muted teal acoustic accent", (0.07, 0.38, 0.42, 1), 0.62),
            "orange": material("warm orange classroom accent", (0.86, 0.36, 0.11, 1), 0.56),
            "purple": material("soft purple display accent", (0.34, 0.22, 0.55, 1), 0.58),
            "sky": material("soft blue outdoor sky", (0.46, 0.72, 0.94, 1), 0.6),
            "night_sky": material("deep night sky outside", (0.015, 0.028, 0.08, 1), 0.7),
            "moon": material("cool moon glow", (0.75, 0.82, 1.0, 1), 0.22, emission=(0.45, 0.56, 1.0, 1), strength=0.7),
            "window_glow": material("warm night window glow", (1.0, 0.72, 0.28, 1), 0.4, emission=(1.0, 0.48, 0.12, 1), strength=0.9),
            "road": material("outside asphalt road", (0.12, 0.13, 0.13, 1), 0.7),
            "outdoor": material("distant muted city blocks", (0.35, 0.48, 0.58, 1), 0.7),
            "outdoor_dark": material("dark distant city blocks", (0.08, 0.11, 0.14, 1), 0.75),
            "copper": material("insulated copper ac pipe", (0.67, 0.32, 0.13, 1), 0.32, metallic=0.25),
            "panel": material("matte charcoal panel", (0.05, 0.06, 0.065, 1), 0.5),
            "screen": material(
                "active smart board screen",
                (0.02, 0.08, 0.12, 1),
                0.24,
                emission=(0.03, 0.36, 0.55, 1),
                strength=0.55,
            ),
            "white": material("satin white laminate", (0.86, 0.88, 0.86, 1), 0.35),
            "desk_edge": material("black powder coated edge", (0.015, 0.016, 0.018, 1), 0.38),
            "metal": material("brushed dark aluminium", (0.22, 0.23, 0.23, 1), 0.25, metallic=0.45),
            "chair": material("quiet blue molded chair", (0.02, 0.24, 0.56, 1), 0.42),
            "chair2": material("sage green molded chair", (0.17, 0.44, 0.34, 1), 0.46),
            "glass": material("clear blue classroom glass", (0.66, 0.86, 1.0, 0.28), 0.08, alpha=0.32),
            "light": material("soft led diffuser", (1.0, 0.96, 0.82, 1), 0.18, emission=(1.0, 0.92, 0.68, 1), strength=1.4),
            "wood": material("light birch wood", (0.72, 0.59, 0.41, 1), 0.4),
            "plant": material("indoor plant leaves", (0.03, 0.42, 0.16, 1), 0.7),
            "pot": material("matte clay planter", (0.58, 0.31, 0.22, 1), 0.65),
            "yellow": material("pinboard warm felt", (0.78, 0.57, 0.18, 1), 0.8),
            "red": material("small red marker", (0.72, 0.08, 0.06, 1), 0.45),
            "blue": material("small blue marker", (0.04, 0.18, 0.78, 1), 0.45),
        }
    )


def cube(name, loc, size, mat=None, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("small rounded edges", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.affect = "EDGES"
        obj.modifiers.new("weighted soft normals", "WEIGHTED_NORMAL")
    return obj


def cyl(name, loc, radius, depth, mat=None, vertices=32, bevel=False):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("soft rim", "BEVEL")
        mod.width = min(radius * 0.15, 0.035)
        mod.segments = 3
        obj.modifiers.new("weighted soft normals", "WEIGHTED_NORMAL")
    try:
        bpy.ops.object.shade_smooth()
    except Exception:
        pass
    return obj


def add_text(name, text, loc, rot, size, mat, align="CENTER", flip_x=True):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = align
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.01
    if flip_x:
        obj.scale.x = -1
    if mat:
        obj.data.materials.append(mat)
    return obj


def hidden(obj):
    obj.hide_viewport = True
    obj.hide_render = True
    return obj


def build_room():
    cube("one piece polished classroom floor", (0, 0, -0.04), (18.4, 13.7, 0.08), MATS["floor"], 0.015)
    for i, x in enumerate([v * 0.75 - 8.625 for v in range(24)]):
        mat = MATS["floor_alt"] if i % 3 == 0 else MATS["floor"]
        cube(f"individual floor plank {i + 1:02d}", (x, 0, 0.012), (0.055, 13.62, 0.012), mat)

    cube("front teaching wall", (0, -6.75, 1.9), (18.4, 0.18, 3.8), MATS["wall"])
    cube("right storage wall", (9.1, 0, 1.9), (0.18, 13.7, 3.8), MATS["wall"])
    cube("back wall with display", (0, 6.75, 1.9), (18.4, 0.18, 3.8), MATS["wall"])
    cube("left lower window wall", (-9.1, 0, 0.65), (0.18, 13.7, 1.3), MATS["wall"])
    cube("left upper window wall beam", (-9.1, 0, 3.5), (0.18, 13.7, 0.3), MATS["wall"])
    cube("clean acoustic ceiling", (0, 0, 3.82), (18.4, 13.7, 0.08), MATS["ceiling"], 0.01)

    cube("exterior day long road visible through windows", (-9.46, 0, 1.03), (0.08, 13.2, 0.34), MATS["road"], 0.004)
    cube("exterior day sidewalk strip", (-9.42, 0, 1.26), (0.06, 13.2, 0.12), MATS["white"], 0.002)
    hidden(cube("exterior night dark road visible through windows", (-9.47, 0, 1.03), (0.08, 13.2, 0.34), MATS["road"], 0.004))
    hidden(cube("exterior night moon panel", (-9.88, -4.65, 3.02), (0.05, 0.48, 0.48), MATS["moon"], 0.02))

    for y in [-5.4, -3.25, -1.1, 1.05, 3.2, 5.35]:
        cube(f"soft blue sky outside window {y}", (-9.92, y, 2.55), (0.04, 1.72, 2.0), MATS["sky"], 0.004)
        hidden(cube(f"night sky outside window {y}", (-9.925, y, 2.55), (0.045, 1.72, 2.0), MATS["night_sky"], 0.004))
        for i, h in enumerate([0.95, 1.35, 1.12]):
            cube(
                f"distant city block {y} {i}",
                (-9.74, y - 0.48 + i * 0.46, 1.42 + h / 2),
                (0.07, 0.34, h),
                MATS["outdoor"],
                0.004,
            )
            for w in [-0.09, 0.08]:
                cube(
                    f"exterior day building window {y} {i} {w}",
                    (-9.685, y - 0.48 + i * 0.46 + w, 1.72 + h * 0.35),
                    (0.018, 0.055, 0.075),
                    MATS["white"],
                    0.001,
                )
            night_block = cube(
                f"exterior night city block {y} {i}",
                (-9.75, y - 0.48 + i * 0.46, 1.42 + h / 2),
                (0.07, 0.34, h),
                MATS["outdoor_dark"],
                0.004,
            )
            hidden(night_block)
            hidden(cube(f"exterior night lit window {y} {i}", (-9.69, y - 0.48 + i * 0.46, 1.76 + h * 0.35), (0.018, 0.16, 0.09), MATS["window_glow"], 0.002))
        for i, ty in enumerate([y - 0.62, y + 0.58]):
            cyl(f"exterior day street tree trunk {y} {i}", (-9.34, ty, 1.34), 0.04, 0.42, MATS["wood"], vertices=10)
            tree = cyl(f"exterior day street tree crown {y} {i}", (-9.34, ty, 1.78), 0.24, 0.28, MATS["plant"], vertices=18, bevel=True)
            tree.rotation_euler[0] = math.radians(90)
            night_tree = cyl(f"exterior night street tree silhouette {y} {i}", (-9.35, ty, 1.76), 0.24, 0.26, MATS["plant"], vertices=18, bevel=True)
            night_tree.rotation_euler[0] = math.radians(90)
            hidden(night_tree)
        cube(f"tall glass window y {y}", (-9.0, y, 2.35), (0.055, 1.7, 1.95), MATS["glass"], 0.015)
        cube(f"black window vertical mullion {y}", (-8.965, y - 0.86, 2.35), (0.08, 0.04, 2.05), MATS["metal"])
        cube(f"black window top rail {y}", (-8.965, y, 3.34), (0.08, 1.82, 0.04), MATS["metal"])
        cube(f"black window sill {y}", (-8.92, y, 1.3), (0.26, 1.88, 0.08), MATS["white"], 0.015)

    cube("modern classroom door slab", (9.005, -5.35, 1.1), (0.08, 1.1, 2.2), MATS["wood"], 0.025)
    cube("narrow door glass insert", (8.955, -5.35, 1.45), (0.035, 0.58, 1.0), MATS["glass"], 0.01)
    cyl("round door handle", (8.9, -4.9, 1.1), 0.055, 0.08, MATS["metal"], vertices=24)
    bpy.context.object.rotation_euler[1] = math.radians(90)


def build_front_wall():
    cube("center traditional blackboard frame", (0, -6.62, 2.14), (5.55, 0.1, 2.08), MATS["metal"], 0.03)
    cube("center matte writing blackboard", (0, -6.555, 2.14), (5.25, 0.035, 1.78), MATS["panel"], 0.012)
    cube("blackboard chalk tray", (0, -6.51, 1.08), (5.75, 0.15, 0.08), MATS["metal"], 0.012)
    for x, mat in [(-1.6, MATS["white"]), (-1.3, MATS["yellow"]), (-1.0, MATS["blue"])]:
        cube(f"chalk stick on tray {x}", (x, -6.42, 1.16), (0.22, 0.035, 0.03), mat, 0.004)

    for side, x, port_x in [("left", -5.35, -4.18), ("right", 5.35, 4.18)]:
        cube(f"{side} thick touch screen body", (x, -6.62, 2.15), (2.35, 0.18, 2.05), MATS["panel"], 0.04)
        cube(f"{side} touch screen glowing glass", (x, -6.50, 2.15), (2.08, 0.035, 1.72), MATS["screen"], 0.018)
        cube(f"{side} touch screen non door side port rail", (port_x, -6.455, 2.14), (0.16, 0.09, 1.48), MATS["metal"], 0.012)
        for i, (z, label, mat) in enumerate(
            [
                (2.72, "USB", MATS["white"]),
                (2.47, "USB-C", MATS["orange"]),
                (2.21, "DP", MATS["blue"]),
                (1.96, "HDMI", MATS["purple"]),
                (1.72, "LAN", MATS["accent"]),
            ]
        ):
            cube(f"{side} touch screen {label} port cutout", (port_x, -6.395, z), (0.1, 0.018, 0.055), MATS["panel"], 0.004)
            cube(f"{side} touch screen {label} colored insert", (port_x, -6.383, z), (0.065, 0.012, 0.032), mat, 0.002)
        cube(f"{side} touchscreen bottom service lip", (x, -6.42, 1.04), (2.35, 0.14, 0.08), MATS["metal"], 0.012)

    cube("main embedded IO bay in left screen right edge", (-4.08, -6.56, 2.18), (0.08, 0.28, 1.16), MATS["metal"], 0.012)
    for i, (y, z, label, mat) in enumerate(
        [
            (-6.63, 2.62, "USB A upper", MATS["white"]),
            (-6.54, 2.62, "USB A lower", MATS["white"]),
            (-6.63, 2.36, "DP output", MATS["blue"]),
            (-6.54, 2.36, "HDMI output", MATS["purple"]),
            (-6.63, 2.10, "USB C output", MATS["orange"]),
            (-6.54, 2.10, "audio lan output", MATS["accent"]),
        ]
    ):
        cube(f"side embedded {label} socket", (-4.025, y, z), (0.018, 0.07, 0.055), MATS["panel"], 0.003)
        cube(f"side embedded {label} colored contact", (-4.012, y, z), (0.012, 0.04, 0.026), mat, 0.002)

    add_text(
        "board title text",
        "55-SEAT CLASSROOM",
        (0, -6.515, 2.72),
        (math.radians(90), 0, 0),
        0.22,
        MATS["light"],
    )
    add_text(
        "board small chinese text",
        "中间黑板 + 双触控屏",
        (0, -6.512, 1.62),
        (math.radians(90), 0, 0),
        0.18,
        MATS["white"],
    )

    cube("raised wood teaching platform deck", (0, -5.38, 0.09), (15.8, 1.95, 0.18), MATS["wood"], 0.035)
    cube("teaching platform dark metal front edge", (0, -4.38, 0.18), (15.9, 0.08, 0.18), MATS["metal"], 0.012)
    cube("warm led strip along teaching platform", (0, -4.32, 0.22), (15.65, 0.035, 0.045), MATS["light"], 0.006)
    cube("wide center step onto platform", (0, -4.08, 0.055), (4.2, 0.48, 0.11), MATS["wood"], 0.025)
    cube("left side step onto platform", (-5.7, -4.1, 0.05), (2.1, 0.42, 0.1), MATS["wood"], 0.02)
    cube("right side step onto platform", (5.7, -4.1, 0.05), (2.1, 0.42, 0.1), MATS["wood"], 0.02)
    for x in [-7.4, -3.7, 0, 3.7, 7.4]:
        cube(f"platform slim accent inlay {x}", (x, -5.38, 0.185), (0.035, 1.66, 0.012), MATS["orange"], 0.002)

    cube("central teacher podium top", (0, -5.28, 0.92), (2.45, 0.9, 0.09), MATS["white"], 0.035)
    cube("central teacher podium body", (0, -5.2, 0.48), (2.28, 0.76, 0.82), MATS["wood"], 0.035)
    cube("recessed computer host inside podium", (0.48, -4.8, 0.52), (0.78, 0.08, 0.48), MATS["panel"], 0.012)
    for i, z in enumerate([0.4, 0.5, 0.6]):
        cube(f"podium computer cooling vent {i}", (0.48, -4.745, z), (0.48, 0.018, 0.025), MATS["metal"], 0.003)
    cyl("podium power button", (0.12, -4.74, 0.67), 0.035, 0.018, MATS["light"], vertices=20)
    bpy.context.object.rotation_euler[0] = math.radians(90)

    cube("flush floor cable trench cover from podium", (0.48, -5.78, 0.205), (0.28, 1.84, 0.035), MATS["metal"], 0.006)
    cube("embedded vertical wall conduit cover", (0.48, -6.505, 1.55), (0.16, 0.018, 1.72), MATS["wall"], 0.004)
    hidden(cube("hidden horizontal conduit inside front wall left", (-1.82, -6.535, 2.55), (4.72, 0.012, 0.075), MATS["wall"], 0.002))
    hidden(cube("hidden horizontal conduit inside front wall right", (2.33, -6.535, 2.3), (3.7, 0.012, 0.075), MATS["wall"], 0.002))
    cube("flush floor conduit under platform to left screen", (-2.05, -5.05, 0.205), (4.15, 0.12, 0.03), MATS["metal"], 0.004)
    cube("flush floor conduit under platform to right screen", (2.4, -5.05, 0.205), (3.8, 0.12, 0.03), MATS["metal"], 0.004)
    for i, (x0, z0) in enumerate([(-4.18, 2.55), (4.18, 2.3)]):
        for offset, mat in [(-0.035, MATS["blue"]), (0.0, MATS["orange"]), (0.035, MATS["purple"])]:
            cube(f"short exposed service tail at screen {i} {offset}", (x0 + offset, -6.37, z0 - 0.22), (0.018, 0.035, 0.24), mat, 0.002)
    for i, (z, mat) in enumerate([(2.62, MATS["blue"]), (2.52, MATS["purple"]), (2.42, MATS["orange"]), (2.32, MATS["white"])]):
        cube(f"short host output jumper inside wall box {i}", (-4.0, -6.355, z), (0.34, 0.032, 0.026), mat, 0.002)


def build_student_set(prefix, x, y, chair_mat, second_chair=True):
    cube(f"{prefix} double desk top", (x, y, 0.73), (1.76, 0.72, 0.07), MATS["white"], 0.035)
    cube(f"{prefix} double desk black edge", (x, y, 0.78), (1.84, 0.8, 0.035), MATS["desk_edge"], 0.018)
    cube(f"{prefix} double desk white inset", (x, y, 0.81), (1.68, 0.64, 0.025), MATS["white"], 0.018)
    cube(f"{prefix} open desk drawer tray", (x, y + 0.28, 0.58), (1.52, 0.34, 0.08), MATS["metal"], 0.012)
    for bx, mat in [(-0.48, MATS["yellow"]), (-0.22, MATS["blue"]), (0.12, MATS["orange"]), (0.42, MATS["purple"])]:
        cube(f"{prefix} book in drawer {bx}", (x + bx, y + 0.3, 0.64), (0.2, 0.27, 0.04), mat, 0.006)
    for dx in [-0.72, 0.72]:
        for dy in [-0.25, 0.25]:
            cyl(f"{prefix} slim table leg {dx} {dy}", (x + dx, y + dy, 0.36), 0.025, 0.68, MATS["metal"], vertices=12)
    for seat_idx, sx in enumerate([-0.46, 0.46]):
        if seat_idx == 1 and not second_chair:
            continue
        seat_y = y + 0.64
        cube(f"{prefix} chair {seat_idx + 1} seat", (x + sx, seat_y, 0.43), (0.52, 0.5, 0.08), chair_mat, 0.05)
        back = cube(f"{prefix} chair {seat_idx + 1} curved back", (x + sx, seat_y + 0.25, 0.82), (0.54, 0.08, 0.72), chair_mat, 0.06)
        back.rotation_euler[0] = math.radians(-8)
        for dx in [-0.2, 0.2]:
            for dy in [-0.17, 0.17]:
                cyl(f"{prefix} chair {seat_idx + 1} leg {dx} {dy}", (x + sx + dx, seat_y + dy, 0.22), 0.022, 0.42, MATS["metal"], vertices=10)


def build_furniture():
    group_xs = [-6.6, -2.2, 2.2, 6.6]
    ys = [-3.65, -2.35, -1.05, 0.25, 1.55, 2.85, 4.15]
    idx = 1
    for group, x in enumerate(group_xs):
        cube(f"group {group + 1} floor color guide", (x, 0.25, 0.018), (2.55, 8.95, 0.018), MATS["white"], 0.012)
        add_text(
            f"group {group + 1} floor label",
            f"GROUP {group + 1}",
            (x, -4.52, 0.055),
            (0, 0, 0),
            0.24,
            MATS["panel"],
            flip_x=False,
        )
        for row, y in enumerate(ys):
            last_single = group == 3 and row == len(ys) - 1
            build_student_set(
                f"group {group + 1} paired desk {row + 1:02d}",
                x,
                y,
                MATS["chair"] if (row + group) % 2 else MATS["chair2"],
                second_chair=not last_single,
            )
            idx += 1

    cube("right wall long low cabinet body", (8.55, 1.1, 0.62), (0.78, 6.2, 1.18), MATS["wood"], 0.04)
    for y in [-1.6, -0.55, 0.5, 1.55, 2.6, 3.65]:
        cube(f"cabinet sliding door {y}", (8.13, y, 0.68), (0.05, 0.86, 0.92), MATS["white"], 0.018)
        cyl(f"cabinet pull {y}", (8.08, y + 0.29, 0.72), 0.025, 0.05, MATS["metal"], vertices=18)
        bpy.context.object.rotation_euler[1] = math.radians(90)

    cube("rich rear class blackboard newspaper frame", (-5.75, 6.62, 2.18), (4.15, 0.08, 1.65), MATS["metal"], 0.025)
    cube("rich rear class blackboard newspaper surface", (-5.75, 6.555, 2.18), (3.9, 0.035, 1.43), MATS["panel"], 0.012)
    add_text(
        "rear blackboard newspaper title",
        "班级黑板报",
        (-5.75, 6.515, 2.78),
        (math.radians(90), 0, math.radians(180)),
        0.2,
        MATS["light"],
    )
    cube("rear blackboard newspaper title underline", (-5.75, 6.505, 2.62), (2.25, 0.025, 0.035), MATS["orange"], 0.003)
    for i, (x, z, sx, sz, mat) in enumerate(
        [
            (-6.9, 2.28, 0.66, 0.46, MATS["yellow"]),
            (-5.82, 2.27, 0.78, 0.5, MATS["white"]),
            (-4.7, 2.27, 0.72, 0.46, MATS["purple"]),
            (-6.88, 1.68, 0.7, 0.42, MATS["blue"]),
            (-5.78, 1.64, 0.82, 0.42, MATS["accent"]),
            (-4.65, 1.66, 0.72, 0.38, MATS["orange"]),
        ]
    ):
        cube(f"rear blackboard report content card {i}", (x, 6.51, z), (sx, 0.025, sz), mat, 0.008)
        cube(f"rear blackboard report card header {i}", (x, 6.49, z + sz * 0.34), (sx * 0.82, 0.018, 0.04), MATS["panel"], 0.003)
    for i, (x, z, mat) in enumerate(
        [
            (-7.2, 2.82, MATS["red"]),
            (-6.6, 2.84, MATS["blue"]),
            (-5.15, 2.83, MATS["orange"]),
            (-4.35, 2.78, MATS["purple"]),
            (-7.1, 1.33, MATS["yellow"]),
            (-4.36, 1.35, MATS["accent"]),
        ]
    ):
        cyl(f"rear blackboard colorful magnet {i}", (x, 6.485, z), 0.045, 0.018, mat, vertices=18)
        bpy.context.object.rotation_euler[0] = math.radians(90)
    for i, x in enumerate([-6.95, -6.55, -5.95, -5.45, -4.95, -4.45]):
        cube(f"rear blackboard chalk line {i}", (x, 6.495, 1.92), (0.26, 0.018, 0.018), MATS["white"], 0.002)

    cube("back collaborative shelf", (5.6, 6.54, 1.0), (3.1, 0.26, 1.8), MATS["wood"], 0.035)
    for z in [0.55, 1.05, 1.55]:
        cube(f"shelf horizontal level {z}", (5.6, 6.36, z), (3.15, 0.34, 0.06), MATS["white"], 0.012)
    for i, x in enumerate([4.45, 4.75, 5.05, 5.55, 5.9, 6.35, 6.65]):
        cube(f"colorful book block {i}", (x, 6.18, 1.28 + (i % 2) * 0.34), (0.16, 0.22, 0.46), MATS["accent"] if i % 2 else MATS["blue"], 0.006)

    cube("rear wall progress display bezel", (0.0, 6.58, 2.35), (3.0, 0.06, 0.96), MATS["panel"], 0.025)
    cube("rear wall progress display glow", (0.0, 6.535, 2.35), (2.75, 0.025, 0.74), MATS["screen"], 0.012)
    for i, (x, h, mat) in enumerate([(-0.38, 0.22, MATS["accent"]), (0.0, 0.38, MATS["orange"]), (0.38, 0.52, MATS["purple"]), (0.76, 0.31, MATS["blue"])]):
        cube(f"rear display analytics bar {i}", (x - 0.25, 6.515, 2.1 + h / 2), (0.22, 0.025, h), mat, 0.006)
    add_text(
        "rear display label",
        "55 STUDENTS",
        (0.0, 6.51, 2.72),
        (math.radians(90), 0, math.radians(180)),
        0.16,
        MATS["white"],
    )

    for i, (x, z, mat) in enumerate([(-1.65, 1.55, MATS["orange"]), (-1.28, 1.86, MATS["purple"]), (-0.92, 1.48, MATS["accent"])]):
        cube(f"rear small acoustic tile {i}", (x, 6.57, z), (0.28, 0.045, 0.42), mat, 0.01)


def build_ceiling_and_decor():
    lights = [
        (-6.4, -4.7), (-2.2, -4.7), (2.2, -4.7), (6.4, -4.7),
        (-6.4, -1.8), (-2.2, -1.8), (2.2, -1.8), (6.4, -1.8),
        (-6.4, 1.1), (-2.2, 1.1), (2.2, 1.1), (6.4, 1.1),
        (-4.2, 4.2), (0, 4.2), (4.2, 4.2),
    ]
    for i, (x, y) in enumerate(lights):
        cube(f"flush rectangular led panel {i}", (x, y, 3.755), (1.55, 0.56, 0.035), MATS["light"], 0.02)
        bpy.ops.object.light_add(type="AREA", location=(x, y, 3.5))
        lamp = bpy.context.object
        lamp.name = f"soft classroom led light {i}"
        lamp.data.energy = 220
        lamp.data.size = 1.35

    for i, (x, y) in enumerate([(-5.3, -2.9), (0, -2.9), (5.3, -2.9), (-5.3, 1.45), (0, 1.45), (5.3, 1.45)]):
        cyl(f"ceiling fan {i} downrod", (x, y, 3.43), 0.028, 0.42, MATS["metal"], vertices=16)
        cyl(f"ceiling fan {i} motor hub", (x, y, 3.18), 0.16, 0.12, MATS["white"], vertices=28, bevel=True)
        for b, angle in enumerate([0, 120, 240]):
            rad = math.radians(angle)
            blade = cube(
                f"ceiling fan {i} blade {b}",
                (x + math.cos(rad) * 0.42, y + math.sin(rad) * 0.42, 3.18),
                (0.86, 0.13, 0.028),
                MATS["white"],
                0.018,
            )
            blade.rotation_euler[2] = rad

    cyl("wall clock rim", (7.75, -6.58, 2.74), 0.27, 0.045, MATS["metal"], vertices=48)
    bpy.context.object.rotation_euler[0] = math.radians(90)
    cyl("wall clock face", (7.75, -6.545, 2.74), 0.235, 0.025, MATS["white"], vertices=48)
    bpy.context.object.rotation_euler[0] = math.radians(90)
    cube("clock minute hand", (7.75, -6.518, 2.8), (0.025, 0.018, 0.19), MATS["panel"], 0.004)
    hand = cube("clock hour hand", (7.81, -6.517, 2.74), (0.15, 0.018, 0.025), MATS["panel"], 0.004)
    hand.rotation_euler[1] = math.radians(25)

    for x, y in [(-8.15, 5.75), (8.2, -1.6), (8.1, 5.55)]:
        cyl(f"plant pot {x} {y}", (x, y, 0.24), 0.22, 0.48, MATS["pot"], vertices=28, bevel=True)
        for i, angle in enumerate([0, 55, 115, 185, 245, 310]):
            leaf = cube(f"plant leaf {x} {y} {i}", (x + math.cos(math.radians(angle)) * 0.18, y + math.sin(math.radians(angle)) * 0.18, 0.73), (0.11, 0.34, 0.04), MATS["plant"], 0.04)
            leaf.rotation_euler[2] = math.radians(angle)
            leaf.rotation_euler[0] = math.radians(18)

    for i, (x, y) in enumerate([(-4.9, 6.58), (4.9, 6.58)]):
        cube(f"rear wall split air conditioner {i} body", (x, y, 3.08), (1.72, 0.12, 0.42), MATS["white"], 0.04)
        cube(f"rear wall split air conditioner {i} black intake line", (x, y - 0.065, 3.2), (1.45, 0.025, 0.035), MATS["panel"], 0.004)
        cube(f"rear wall split air conditioner {i} lower vent", (x, y - 0.075, 2.91), (1.35, 0.035, 0.06), MATS["metal"], 0.004)
        cube(f"rear ac wall penetration sleeve {i}", (x + 0.78, 6.71, 3.02), (0.18, 0.08, 0.18), MATS["metal"], 0.008)
        cube(f"rear ac insulated pipe indoor cover {i}", (x + 0.78, 6.62, 2.78), (0.12, 0.07, 0.55), MATS["white"], 0.008)
        cube(f"rear exterior condenser unit {i} body", (x + 0.78, 7.02, 2.46), (1.18, 0.42, 0.72), MATS["white"], 0.035)
        cyl(f"rear exterior condenser unit {i} fan grille", (x + 0.78, 6.78, 2.46), 0.25, 0.025, MATS["metal"], vertices=32)
        bpy.context.object.rotation_euler[0] = math.radians(90)
        for dx in [-0.32, 0.0, 0.32]:
            cube(f"rear exterior condenser grille slat {i} {dx}", (x + 0.78 + dx, 6.765, 2.46), (0.035, 0.018, 0.48), MATS["metal"], 0.002)
        cube(f"rear exterior condenser wall bracket left {i}", (x + 0.28, 6.92, 2.02), (0.12, 0.5, 0.06), MATS["metal"], 0.006)
        cube(f"rear exterior condenser wall bracket right {i}", (x + 1.28, 6.92, 2.02), (0.12, 0.5, 0.06), MATS["metal"], 0.006)
        cube(f"rear ac copper line to outdoor unit {i}", (x + 0.78, 6.88, 2.82), (0.055, 0.35, 0.55), MATS["copper"], 0.006)
        cube(f"rear ac white drain line to outdoor unit {i}", (x + 0.92, 6.9, 2.72), (0.04, 0.38, 0.64), MATS["white"], 0.004)
    for i, y in enumerate([-1.75, 2.55]):
        cube(f"right wall split air conditioner {i} body", (9.0, y, 3.04), (0.12, 1.65, 0.42), MATS["white"], 0.04)
        cube(f"right wall split air conditioner {i} lower vent", (8.925, y, 2.88), (0.035, 1.32, 0.055), MATS["metal"], 0.004)
        cube(f"right wall split air conditioner {i} status light", (8.91, y + 0.62, 3.14), (0.025, 0.08, 0.035), MATS["light"], 0.002)
        cube(f"right ac wall penetration sleeve {i}", (9.12, y + 0.72, 3.0), (0.08, 0.18, 0.18), MATS["metal"], 0.008)
        cube(f"right ac insulated pipe indoor cover {i}", (9.06, y + 0.72, 2.76), (0.07, 0.12, 0.56), MATS["white"], 0.008)
        cube(f"right exterior condenser unit {i} body", (9.42, y + 0.72, 2.42), (0.42, 1.18, 0.72), MATS["white"], 0.035)
        cyl(f"right exterior condenser unit {i} fan grille", (9.18, y + 0.72, 2.42), 0.25, 0.025, MATS["metal"], vertices=32)
        bpy.context.object.rotation_euler[1] = math.radians(90)
        for dy in [-0.32, 0.0, 0.32]:
            cube(f"right exterior condenser grille slat {i} {dy}", (9.165, y + 0.72 + dy, 2.42), (0.018, 0.035, 0.48), MATS["metal"], 0.002)
        cube(f"right exterior condenser wall bracket low {i}", (9.32, y + 0.22, 2.0), (0.5, 0.12, 0.06), MATS["metal"], 0.006)
        cube(f"right exterior condenser wall bracket high {i}", (9.32, y + 1.22, 2.0), (0.5, 0.12, 0.06), MATS["metal"], 0.006)
        cube(f"right ac copper line to outdoor unit {i}", (9.26, y + 0.72, 2.78), (0.34, 0.055, 0.52), MATS["copper"], 0.006)
        cube(f"right ac white drain line to outdoor unit {i}", (9.28, y + 0.88, 2.66), (0.38, 0.04, 0.66), MATS["white"], 0.004)

    cube("main classroom switch control panel", (8.99, -4.25, 1.42), (0.04, 0.72, 0.9), MATS["white"], 0.018)
    for i, (dy, z, mat) in enumerate([(-0.22, 1.68, MATS["light"]), (0.0, 1.68, MATS["blue"]), (0.22, 1.68, MATS["accent"]), (-0.22, 1.42, MATS["orange"]), (0.0, 1.42, MATS["purple"]), (0.22, 1.42, MATS["panel"])]):
        cube(f"wall switch button {i}", (8.955, -4.25 + dy, z), (0.025, 0.11, 0.085), mat, 0.006)
    cyl("day mode sun selector button", (8.95, -4.47, 1.16), 0.055, 0.022, MATS["yellow"], vertices=20)
    bpy.context.object.rotation_euler[1] = math.radians(90)
    cyl("night mode moon selector button", (8.95, -4.22, 1.16), 0.055, 0.022, MATS["moon"], vertices=20)
    bpy.context.object.rotation_euler[1] = math.radians(90)
    cube("fan speed rotary control", (8.955, -4.0, 1.16), (0.025, 0.13, 0.13), MATS["metal"], 0.01)
    cube("air conditioner thermostat panel", (8.99, -3.55, 1.55), (0.04, 0.42, 0.5), MATS["white"], 0.014)
    cube("thermostat blue display", (8.955, -3.55, 1.66), (0.025, 0.26, 0.11), MATS["screen"], 0.004)
    for i, z in enumerate([1.47, 1.36]):
        cube(f"thermostat small button {i}", (8.955, -3.55, z), (0.025, 0.08, 0.055), MATS["metal"], 0.004)


def setup_lighting_camera():
    bpy.ops.object.light_add(type="SUN", location=(-4, -3, 6))
    sun = bpy.context.object
    sun.name = "DAY MODE soft daylight from window wall"
    sun.data.energy = 2.1
    sun.rotation_euler = (math.radians(45), 0, math.radians(-32))

    bpy.ops.object.light_add(type="SUN", location=(-5, 2, 6))
    moon = bpy.context.object
    moon.name = "NIGHT MODE cool moonlight from window wall"
    moon.data.energy = 0.35
    moon.rotation_euler = (math.radians(58), 0, math.radians(-76))
    moon.hide_viewport = True
    moon.hide_render = True

    bpy.ops.object.camera_add(location=(8.15, 5.35, 2.35), rotation=(math.radians(61), 0, math.radians(135)))
    cam = bpy.context.object
    cam.name = "interior overview camera"
    bpy.context.scene.camera = cam
    direction = Vector((0.0, -1.75, 1.35)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 19
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = 8.0
    cam.data.dof.aperture_fstop = 8.0

    bpy.context.scene.render.engine = "CYCLES"
    bpy.context.scene.cycles.samples = 96
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.view_settings.look = "Medium High Contrast"
    bpy.context.scene.world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world.color = (0.9, 0.93, 0.96)
    bpy.context.scene.render.resolution_x = 1600
    bpy.context.scene.render.resolution_y = 1000


def organize_scene():
    collection = bpy.data.collections.new("Modern Classroom Generated Assets")
    bpy.context.scene.collection.children.link(collection)
    for obj in bpy.context.scene.objects:
        if obj.name not in collection.objects:
            try:
                collection.objects.link(obj)
            except RuntimeError:
                pass


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    clear_scene()
    init_materials()
    build_room()
    build_front_wall()
    build_furniture()
    build_ceiling_and_decor()
    setup_lighting_camera()
    organize_scene()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


if __name__ == "__main__":
    main()
