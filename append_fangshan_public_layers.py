import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_school_campus as campus


ROOT = os.environ.get("SCHOOL_ROOT", os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.environ.get("SCHOOL_BLEND", os.path.join(ROOT, "school_campus.blend"))


def object_exists(name):
    return name in bpy.data.objects


def append_layers():
    campus.MATS.clear()
    campus.init_materials()
    if not object_exists("设施索引_南外方山公开资料复刻层"):
        campus.make_fangshan_public_reference_reconstruction()
    if not object_exists("设施索引_南外方山高相似公开细化层"):
        campus.make_fangshan_high_fidelity_public_details()
    if not object_exists("设施索引_南外方山公开课程庭院细节层"):
        campus.make_fangshan_program_courtyard_details()
    if not object_exists("设施索引_游戏主教学楼_导航交互"):
        campus.make_game_navigation_interaction_markers()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    campus.render_previews()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


if __name__ == "__main__":
    append_layers()
