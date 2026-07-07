import math
import os
import subprocess

import bpy
from mathutils import Vector


ROOT = os.environ.get("CLASSROOM_ROOT", os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.environ.get("CLASSROOM_BLEND", os.path.join(ROOT, "classroom.blend"))
OUT_DIR = os.environ.get("CLASSROOM_PREVIEW_DIR", os.path.join(ROOT, "previews"))


VIEWS = [
    ("01_后排总览", (8.1, 5.35, 2.35), (0.0, -1.7, 1.35), 19),
    ("02_讲台正面", (0.0, 2.05, 1.65), (0.0, -6.55, 2.05), 23),
    ("03_四组桌椅斜视", (-8.0, 5.5, 1.45), (0.0, -1.1, 0.95), 20),
    ("04_窗边看大教室", (-8.4, 0.4, 1.75), (2.3, -1.4, 1.2), 21),
    ("05_右侧储物柜", (8.35, 4.6, 1.75), (2.4, -0.6, 1.15), 23),
    ("06_黑板干净近景", (3.6, -4.65, 1.75), (0.0, -6.54, 2.08), 31),
    ("07_桌斗书本近景", (-3.55, -1.62, 0.64), (-2.2, -2.05, 0.6), 48),
    ("08_顶视布局", (0.0, 0.0, 11.5), (0.0, 0.0, 0.0), 32),
    ("09_教室后墙", (-6.8, -1.0, 1.85), (0.0, 6.55, 1.75), 23),
    ("10_接口排线近景", (-3.35, -4.95, 2.35), (-4.08, -6.54, 2.32), 48),
    ("11_讲台地台近景", (4.8, -3.25, 1.25), (0.0, -5.35, 0.45), 30),
    ("12_夜间模式总览", (8.1, 5.35, 2.35), (0.0, -1.7, 1.35), 19),
    ("13_空调风扇开关", (8.15, -3.0, 1.85), (8.98, -4.05, 1.55), 42),
]


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def ensure_camera(name, loc, target, lens):
    cam_data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = loc
    look_at(cam, target)
    cam.data.lens = lens
    cam.data.dof.use_dof = False
    return cam


def set_top_camera(cam):
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 15.2


def set_fast_renderer():
    try:
        bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
        bpy.context.scene.eevee.taa_render_samples = 64
    except Exception:
        bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
    bpy.context.scene.render.resolution_x = 1400
    bpy.context.scene.render.resolution_y = 875
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.view_settings.look = "Medium High Contrast"


def set_day_night_mode(night=False):
    for obj in bpy.data.objects:
        name = obj.name.lower()
        is_night_exterior = name.startswith("exterior night") or name.startswith("night sky outside")
        is_day_exterior = name.startswith("exterior day") or name.startswith("soft blue sky") or name.startswith("distant city block")
        if is_night_exterior:
            obj.hide_viewport = not night
            obj.hide_render = not night
        if is_day_exterior:
            obj.hide_viewport = night
            obj.hide_render = night
        if obj.type == "LIGHT" and obj.name.startswith("DAY MODE"):
            obj.hide_viewport = night
            obj.hide_render = night
        if obj.type == "LIGHT" and obj.name.startswith("NIGHT MODE"):
            obj.hide_viewport = not night
            obj.hide_render = not night
    if bpy.context.scene.world:
        bpy.context.scene.world.color = (0.018, 0.025, 0.055) if night else (0.9, 0.93, 0.96)


def make_contact_sheet():
    script = f"""
import os
from PIL import Image, ImageDraw

out_dir = {OUT_DIR!r}
files = [os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir)) if f.endswith('.png') and f[:2].isdigit()]
thumb_w, thumb_h = 560, 350
cols = 2
rows = (len(files) + cols - 1) // cols
sheet = Image.new('RGB', (cols * thumb_w, rows * (thumb_h + 34)), (235, 235, 235))
draw = ImageDraw.Draw(sheet)
for idx, path in enumerate(files):
    img = Image.open(path).convert('RGB')
    img.thumbnail((thumb_w, thumb_h), Image.LANCZOS)
    x = (idx % cols) * thumb_w + (thumb_w - img.width) // 2
    y = (idx // cols) * (thumb_h + 34)
    sheet.paste(img, (x, y))
    draw.text(((idx % cols) * thumb_w + 14, y + thumb_h + 8), f'view {{idx + 1:02d}}', fill=(20, 20, 20))
sheet.save(os.path.join(out_dir, '00_总览拼图.png'))
"""
    subprocess.run(["python3", "-c", script], check=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for filename in os.listdir(OUT_DIR):
        if filename.endswith(".png") and (filename[:2].isdigit() or filename.startswith("00_")):
            os.remove(os.path.join(OUT_DIR, filename))
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    set_fast_renderer()
    for name, loc, target, lens in VIEWS:
        set_day_night_mode(night=name.startswith("12_"))
        cam = ensure_camera(f"render camera {name}", loc, target, lens)
        hidden = []
        if name.startswith("08_"):
            set_top_camera(cam)
            for obj in bpy.data.objects:
                if "ceiling" in obj.name.lower():
                    hidden.append((obj, obj.hide_render))
                    obj.hide_render = True
        bpy.context.scene.camera = cam
        bpy.context.scene.render.filepath = os.path.join(OUT_DIR, f"{name}.png")
        bpy.ops.render.render(write_still=True)
        for obj, old_value in hidden:
            obj.hide_render = old_value
    make_contact_sheet()


if __name__ == "__main__":
    main()
