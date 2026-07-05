import os
import sys

try:
    import bpy
except ImportError as exc:
    raise SystemExit("Run this script with Blender Python, for example: blender -b school_campus.blend --python verify_school_campus.py") from exc


ROOT = os.environ.get("SCHOOL_ROOT", os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.environ.get("SCHOOL_BLEND", os.path.join(ROOT, "school_campus.blend"))

REQUIRED_KEYWORDS = [
    "微机室",
    "服务器机房",
    "配电室",
    "监控室",
    "保安室",
    "操场",
    "室内操场",
    "普通教室",
    "科技运维楼",
    "食堂",
    "宿舍",
    "STEM",
    "图书馆",
    "CCTV",
    "transformer",
    "fiber",
    "power",
    "中心水景",
    "物理实验室",
    "化学实验室",
    "生物实验室",
    "AI创客",
    "VR沉浸",
    "机器人",
    "报告厅",
    "校车",
    "自行车",
    "无障碍",
    "solar",
    "rainwater",
    "fire hydrant",
    "evacuation",
    "broadcast",
    "数字孪生",
    "楼层剖面",
    "食堂内部",
    "宿舍内部",
    "室内操场内部",
    "地下综合管廊",
    "疏散集结点",
    "校园围墙",
    "消防车道",
    "后勤装卸区",
    "垃圾分类站",
    "语言实验室",
    "美术教室",
    "音乐教室",
    "校史馆",
    "教师发展中心",
    "家长接待室",
    "卫生间",
    "电梯",
    "门禁",
    "校医诊室",
    "隔离观察室",
    "心理咨询室",
    "气象站",
    "空气质量",
]


def main():
    if bpy.data.filepath != os.path.abspath(BLEND_PATH):
        bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    names = [obj.name for obj in bpy.data.objects]
    missing = []
    for keyword in REQUIRED_KEYWORDS:
        count = sum(keyword.lower() in name.lower() for name in names)
        print(f"{keyword}: {count}")
        if count == 0:
            missing.append(keyword)
    print(f"OBJECT_COUNT: {len(names)}")
    if missing:
        print("MISSING: " + ", ".join(missing))
        return 1
    print("VERIFY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
