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
    "图书馆内部",
    "阅览区",
    "自助借还机",
    "体育更衣室",
    "淋浴间",
    "体育器材室",
    "裁判医务点",
    "校园导视屏",
    "AED急救箱",
    "应急电话",
    "饮水点",
    "储物柜",
    "电子班牌",
    "访客服务终端",
    "充电服务站",
    "分区边界",
    "入口共享区",
    "教学静区",
    "运动活力区",
    "生活后勤区",
    "后勤车行门岗",
    "应急门",
    "访客停车场",
    "教职工停车场",
    "行政办公剖面",
    "校长室",
    "教务处",
    "总务处",
    "财务室",
    "档案室",
    "化学品暂存柜",
    "危废暂存箱",
    "通风橱",
    "紧急冲淋洗眼器",
    "生物安全柜",
    "空调能源站",
    "冷水机组",
    "循环水泵",
    "消防水池",
    "消防泵房",
    "生活水泵房",
    "弱电间IDF节点",
    "楼宇自控BAS",
    "一键日夜模式",
    "室外照明回路",
    "操场看台",
    "操场主席台",
    "操场电子记分屏",
    "跳远沙坑",
    "铅球投掷区",
    "露天剧场",
    "阅读花园",
    "生态课程湿地",
    "劳动教育菜园",
    "校园温室",
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
