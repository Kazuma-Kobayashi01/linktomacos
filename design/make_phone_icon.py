#!/usr/bin/env python3
"""生成“投屏助手”App 的图标：和主程序图标同一套白色圆角方形底板和手机画法，但只有手机（没有笔记本）。

投屏助手是独立的 App，投屏时在 Dock 里有自己的图标，一眼能和主程序区分开。
输出：macos/LinkMirror/Assets.xcassets/AppIcon.appiconset/*（含 Contents.json）
用法：python3 design/make_phone_icon.py
"""
import json
from pathlib import Path

from PIL import Image

import make_icon as m

ROOT = m.ROOT
PHONE_HEIGHT_FRACTION = 0.66  # 手机高度占底板高度的比例


def place_by_height(plate, logo):
    """把只有手机的 logo 缩放到指定高度，居中放在底板上（make_icon.place_logo 是按宽度缩放的，窄长的手机不适用）。"""
    x0, y0, x1, y1 = logo.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    margin = 100 * m.SS
    crop_box = (max(0, x0 - margin), max(0, y0 - margin), min(m.S, x1 + margin), min(m.S, y1 + margin))
    cropped = logo.crop(crop_box)
    scale = (m.PLATE[3] - m.PLATE[1]) * m.SS * PHONE_HEIGHT_FRACTION / (y1 - y0)
    cropped = cropped.resize((round(cropped.width * scale), round(cropped.height * scale)), Image.LANCZOS)
    center_x = ((x0 + x1) / 2 - crop_box[0]) * scale
    center_y = ((y0 + y1) / 2 - crop_box[1]) * scale
    plate_x = (m.PLATE[0] + m.PLATE[2]) / 2 * m.SS
    plate_y = (m.PLATE[1] + m.PLATE[3]) / 2 * m.SS
    plate.alpha_composite(cropped, (round(plate_x - center_x), round(plate_y - center_y)))


def main():
    logo = Image.new("RGBA", (m.S, m.S), (0, 0, 0, 0))
    m.draw_phone(logo)
    canvas = m.plate_layer()
    place_by_height(canvas, logo)
    master = canvas.resize((1024, 1024), Image.LANCZOS)

    catalog = ROOT / "macos/LinkMirror/Assets.xcassets"
    iconset = catalog / "AppIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for old in iconset.glob("*.png"):
        old.unlink()
    images = []
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            master.resize((base * scale, base * scale), Image.LANCZOS).save(iconset / name)
            images.append({"idiom": "mac", "size": f"{base}x{base}", "scale": f"{scale}x", "filename": name})
    (iconset / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    print("ok")


if __name__ == "__main__":
    main()
