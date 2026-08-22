#!/usr/bin/env python3
"""键盘布局自动验收：截图 → 像素分析 → 输出文字结论。

存在意义：当前模型无法读图，因此把「看图」变成「读数」。
用法：python3 Scripts/kb_layout_check.py [out.png]
"""
import subprocess
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/kb_shot.png"


def shot(path: str) -> None:
    subprocess.run(
        ["python3", "-m", "pymobiledevice3", "developer", "dvt", "screenshot", path],
        check=True, capture_output=True, timeout=120,
    )


def analyze(path: str) -> None:
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    print(f"屏幕 {W}x{H}")

    # 键盘位于屏幕下半部分。逐行统计「亮色像素」（按键为白/浅灰）占该行宽度的比例。
    # 键盘所在行应有大量亮色像素横跨整宽；若只集中在中间一小段 → 键盘没铺满。
    rows = []
    for y in range(H // 2, H, 4):
        light = [x for x in range(0, W, 4) if min(px[x, y]) > 175]
        if len(light) < 3:
            rows.append((y, 0, 0, 0))
            continue
        rows.append((y, len(light) * 4, min(light), max(light)))

    kb_rows = [r for r in rows if r[1] > W * 0.25]
    if not kb_rows:
        print("❌ 下半屏没找到键盘特征（大面积亮色按键）——键盘可能未显示")
        return

    top = kb_rows[0][0]
    bottom = kb_rows[-1][0]
    left = min(r[2] for r in kb_rows)
    right = max(r[3] for r in kb_rows)
    span = right - left
    ratio = span / W

    print(f"键盘区域  y {top}–{bottom}  高 {bottom - top}px")
    print(f"水平范围  x {left}–{right}  跨度 {span}px = 屏宽 {ratio:.0%}")

    if ratio > 0.92:
        print("✅ 已铺满屏宽")
    elif ratio > 0.6:
        print(f"⚠️  只占 {ratio:.0%}，未铺满（疑似宽度约束缺失）")
    else:
        print(f"❌ 只占 {ratio:.0%} —— 典型「单手键盘」窄条形态")

    # 左右留白是否对称：不对称说明被推到一侧
    if abs(left - (W - right)) > W * 0.06:
        print(f"⚠️  左右留白不对称：左 {left}px / 右 {W - right}px —— 键盘偏向一侧")
    else:
        print(f"留白对称：左 {left}px / 右 {W - right}px")

    exp_h = 290 * H / 2796  # 期望高度（按 Metric.kbHeight 折算到物理像素）
    print(f"高度参考：实测 {bottom - top}px，期望约 {exp_h * 2:.0f}px（含候选区）")


if __name__ == "__main__":
    shot(OUT)
    analyze(OUT)
