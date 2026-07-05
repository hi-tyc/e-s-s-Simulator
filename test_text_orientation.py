import math
import os

import bpy
from mathutils import Vector


ROOT = os.environ.get("CLASSROOM_ROOT", os.path.dirname(os.path.abspath(__file__)))


def mat(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = color
    return m


def add_text(label, loc, rot, scale_x=1):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    o = bpy.context.object
    o.name = label
    o.data.body = "ABC"
    o.data.align_x = "CENTER"
    o.data.align_y = "CENTER"
    o.data.size = 0.42
    o.data.extrude = 0.01
    o.scale.x = scale_x
    o.data.materials.append(TEXT)
    return o


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
TEXT = mat("text", (1, 1, 1, 1))
BOARD = mat("board", (0.02, 0.06, 0.08, 1))

bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -4, 1.8))
board = bpy.context.object
board.dimensions = (5.5, 0.08, 2.2)
board.data.materials.append(BOARD)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

cases = [
    ("rx90", (-2.2, -3.93, 2.75), (math.radians(90), 0, 0), 1),
    ("rx90 sx-1", (0, -3.93, 2.75), (math.radians(90), 0, 0), -1),
    ("rx90 rz180", (2.2, -3.93, 2.75), (math.radians(90), 0, math.radians(180)), 1),
    ("rx-90", (-2.2, -3.93, 2.0), (math.radians(-90), 0, 0), 1),
    ("rx-90 sx-1", (0, -3.93, 2.0), (math.radians(-90), 0, 0), -1),
    ("rx-90 rz180", (2.2, -3.93, 2.0), (math.radians(-90), 0, math.radians(180)), 1),
    ("rx90 ry180", (-1.1, -3.93, 1.25), (math.radians(90), math.radians(180), 0), 1),
    ("rx-90 ry180", (1.1, -3.93, 1.25), (math.radians(-90), math.radians(180), 0), 1),
]
for c in cases:
    add_text(*c)

bpy.ops.object.camera_add(location=(0, 0.4, 2.0))
cam = bpy.context.object
bpy.context.scene.camera = cam
direction = Vector((0, -4, 2.0)) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
cam.data.lens = 35

bpy.ops.object.light_add(type="AREA", location=(0, -1, 4))
l = bpy.context.object
l.data.energy = 500
l.data.size = 4

bpy.context.scene.render.resolution_x = 900
bpy.context.scene.render.resolution_y = 560
bpy.context.scene.render.filepath = os.path.join(ROOT, "text_orientation_test.png")
try:
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
except Exception:
    bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
bpy.ops.render.render(write_still=True)
