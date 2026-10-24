#!/usr/bin/env python3
"""生成 macOS App 图标：一台笔记本电脑 + 前方一部 Material 3 风格的手机。

笔记本和手机都是原创绘制。手机配色取自 Material 3 基准色板（种子色蓝）：
    primary #415F91   primaryContainer #D6E3FF   secondary #565F71   secondaryContainer #DAE2F9
    tertiary #705575  tertiaryContainer #FAD8FD  surface #F9F9FF

输出：macos/LinkToMacOS/Assets.xcassets/AppIcon.appiconset/*（含 Contents.json）
用法：python3 design/make_icon.py

Android 图标是手写的矢量文件（android/app/src/main/res/drawable/ic_launcher_*.xml），
颜色直接引用系统调色盘，不由本脚本生成。
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SS = 2  # 超采样倍数
S = 1024 * SS
OY = 40  # 整体下移，让图案在画布中垂直居中


def px(box):
    x0, y0, x1, y1 = box
    return [round(x0 * SS), round((y0 + OY) * SS), round(x1 * SS), round((y1 + OY) * SS)]


def gradient(size, top, bottom):
    w, h = size
    mask = Image.linear_gradient("L").resize((1, h)).resize((w, h))
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), mask)


def shape_mask(size, radius, corners=(True, True, True, True)):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius * SS, fill=255, corners=corners)
    return mask


def gradient_box(layer, box, radius, top, bottom, corners=(True, True, True, True)):
    x0, y0, x1, y1 = px(box)
    size = (x1 - x0, y1 - y0)
    layer.paste(gradient(size, top, bottom), (x0, y0), shape_mask(size, radius, corners))


def solid_box(layer, box, radius, color, corners=(True, True, True, True)):
    x0, y0, x1, y1 = px(box)
    size = (x1 - x0, y1 - y0)
    tile = Image.new("RGBA", size, color)
    tile.putalpha(shape_mask(size, radius, corners).point(lambda a: a * color[3] // 255 if len(color) == 4 else a))
    layer.alpha_composite(tile, (x0, y0))


def circle(layer, cx, cy, r, color):
    x0, y0, x1, y1 = px((cx - r, cy - r, cx + r, cy + r))
    tile = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    ImageDraw.Draw(tile).ellipse((0, 0, x1 - x0 - 1, y1 - y0 - 1), fill=color)
    layer.alpha_composite(tile, (x0, y0))


def soft_shadow(layer, box, radius, blur, dy, opacity):
    x0, y0, x1, y1 = px(box)
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x0, y0 + dy * SS, x1, y1 + dy * SS), radius * SS, fill=(8, 20, 50, int(255 * opacity)))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur * SS)))


def draw_laptop(img):
    # 桌面投影
    soft_shadow(img, (80, 700, 944, 740), 20, 26, 14, 0.50)

    # 机身：深色边框的屏幕盖
    gradient_box(img, (112, 170, 912, 670), 40, (52, 54, 60), (22, 23, 26))

    # 屏幕：蓝色桌面壁纸，叠两层柔和的亮带
    screen = (136, 194, 888, 646)
    gradient_box(img, screen, 22, (66, 128, 214), (130, 184, 246))
    x0, y0, x1, y1 = px(screen)
    size = (x1 - x0, y1 - y0)
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-int(size[0] * 0.2), int(size[1] * 0.35), int(size[0] * 0.75), int(size[1] * 1.5)), fill=(255, 255, 255, 46))
    gd.ellipse((int(size[0] * 0.3), int(size[1] * 0.55), int(size[0] * 1.3), int(size[1] * 1.6)), fill=(255, 255, 255, 34))
    glow = glow.filter(ImageFilter.GaussianBlur(40 * SS))
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", size, 0), shape_mask(size, 22)))
    img.alpha_composite(glow, (x0, y0))

    # 刘海和摄像头
    solid_box(img, (440, 194, 584, 232), 20, (14, 15, 17, 255), corners=(False, False, True, True))
    circle(img, 512, 209, 6, (38, 52, 74, 255))

    # 底座：转轴缝、银色底座、前缘凹槽
    solid_box(img, (100, 664, 924, 674), 4, (0, 0, 0, 120))
    gradient_box(img, (72, 670, 952, 724), 28, (226, 228, 233), (166, 170, 179), corners=(False, False, True, True))
    gradient_box(img, (432, 670, 592, 694), 14, (150, 153, 162), (124, 127, 136), corners=(False, False, True, True))


def draw_phone(img):
    x0, y0, x1, y1 = 640, 420, 868, 830
    soft_shadow(img, (x0, y0, x1, y1), 58, 24, 26, 0.55)

    # 机身：primary，屏幕：surface
    gradient_box(img, (x0, y0, x1, y1), 58, (70, 102, 155), (58, 86, 136))
    solid_box(img, (x0 + 12, y0 + 12, x1 - 12, y1 - 12), 47, (249, 249, 255, 255))

    # 屏幕内容：打孔摄像头、标题栏、两张卡片、悬浮按钮、手势条
    circle(img, 754, 456, 8, (26, 28, 32, 255))
    solid_box(img, (672, 486, 800, 512), 13, (65, 95, 145, 255))

    solid_box(img, (672, 530, 836, 608), 20, (214, 227, 255, 255))
    circle(img, 703, 569, 15, (65, 95, 145, 255))
    solid_box(img, (729, 555, 812, 565), 5, (86, 95, 113, 255))
    solid_box(img, (729, 575, 792, 585), 5, (140, 148, 165, 255))

    solid_box(img, (672, 622, 836, 692), 20, (218, 226, 249, 255))
    circle(img, 703, 657, 15, (86, 95, 113, 255))
    solid_box(img, (729, 643, 812, 653), 5, (86, 95, 113, 255))
    solid_box(img, (729, 663, 792, 673), 5, (140, 148, 165, 255))

    solid_box(img, (768, 726, 836, 794), 22, (250, 216, 253, 255))
    solid_box(img, (788, 757, 816, 763), 3, (112, 85, 117, 255))
    solid_box(img, (799, 746, 805, 774), 3, (112, 85, 117, 255))
    solid_box(img, (724, 804, 784, 810), 3, (110, 114, 124, 255))


def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_laptop(canvas)
    draw_phone(canvas)
    master = canvas.resize((1024, 1024), Image.LANCZOS)

    iconset = ROOT / "macos/LinkToMacOS/Assets.xcassets/AppIcon.appiconset"
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
    (iconset.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    print("ok")


if __name__ == "__main__":
    main()
