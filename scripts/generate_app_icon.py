#!/usr/bin/env python3
"""
FutaFinance アプリアイコンを生成する。

デザイン:
  - 1024x1024 PNG
  - 紺(#1A237E)→オレンジ(#EA580C) のグラデーション（事業×個人モード両対応）
  - 中央に「財」漢字（白、太字）
  - 角丸（iOS スタイル、半径 22%）

出力先:
  apps/futa_finance/assets/icon/app_icon.png        メインアイコン（透過なし）
  apps/futa_finance/assets/icon/app_icon_fg.png    Android Adaptive Foreground
  apps/futa_finance/assets/icon/app_icon_bg.png    Android Adaptive Background

実行後、flutter_launcher_icons で Android/Web/iOS/Windows の各サイズに展開:
  cd apps/futa_finance && dart run flutter_launcher_icons
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "apps", "futa_finance", "assets", "icon"
)
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 1024

# ───────────────────────────────────────────
# 1. メインアイコン（背景グラデ + 角丸 + 「財」）
# ───────────────────────────────────────────


def make_gradient(size, top_color, bottom_color):
    """対角線グラデーション（左上=top_color, 右下=bottom_color）。"""
    base = Image.new("RGB", (size, size), bottom_color)
    top = Image.new("RGB", (size, size), top_color)
    # 対角マスク
    mask = Image.new("L", (size, size))
    for y in range(size):
        for x in range(size):
            # 0=top_color(左上), 255=bottom_color(右下)
            ratio = ((x + y) / (2 * size - 2))
            mask.putpixel((x, y), int(ratio * 255))
    base.paste(top, (0, 0), Image.eval(mask, lambda v: 255 - v))
    return base


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def find_font(size_px):
    candidates = [
        # Windows
        r"C:\Windows\Fonts\YuGothB.ttc",
        r"C:\Windows\Fonts\meiryob.ttc",
        r"C:\Windows\Fonts\msgothic.ttc",
        r"C:\Windows\Fonts\YuGothM.ttc",
        # macOS / Linux fallback（仮）
        "/System/Library/Fonts/PingFang.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for f in candidates:
        if os.path.exists(f):
            try:
                return ImageFont.truetype(f, size_px)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_main_icon():
    # グラデーション背景（紺→オレンジ）
    bg = make_gradient(SIZE, (26, 35, 126), (234, 88, 12))

    # 角丸クロップ
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.paste(bg, (0, 0), rounded_mask(SIZE, int(SIZE * 0.22)))

    # 「財」漢字（白）
    draw = ImageDraw.Draw(img)
    font = find_font(int(SIZE * 0.62))
    text = "財"
    # 影で立体感
    shadow_offset = int(SIZE * 0.012)
    draw.text(
        (SIZE // 2 + shadow_offset, SIZE // 2 + shadow_offset),
        text,
        font=font,
        fill=(0, 0, 0, 90),
        anchor="mm",
    )
    draw.text(
        (SIZE // 2, SIZE // 2),
        text,
        font=font,
        fill=(255, 255, 255, 255),
        anchor="mm",
    )

    out = os.path.join(OUT_DIR, "app_icon.png")
    img.save(out, "PNG")
    print(f"[OK] {out}")


# ───────────────────────────────────────────
# 2. Android Adaptive: Foreground のみ（透過）
# ───────────────────────────────────────────


def draw_adaptive_foreground():
    """Android Adaptive Icon の foreground (透過背景 + 中央に「財」)。
    Adaptive Icon は中央 66% に safe zone があるので、文字は小さめ。
    """
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = find_font(int(SIZE * 0.45))
    draw.text(
        (SIZE // 2, SIZE // 2),
        "財",
        font=font,
        fill=(255, 255, 255, 255),
        anchor="mm",
    )
    out = os.path.join(OUT_DIR, "app_icon_fg.png")
    img.save(out, "PNG")
    print(f"[OK] {out}")


# ───────────────────────────────────────────
# 3. Android Adaptive: Background (グラデのみ)
# ───────────────────────────────────────────


def draw_adaptive_background():
    bg = make_gradient(SIZE, (26, 35, 126), (234, 88, 12))
    out = os.path.join(OUT_DIR, "app_icon_bg.png")
    bg.save(out, "PNG")
    print(f"[OK] {out}")


if __name__ == "__main__":
    draw_main_icon()
    draw_adaptive_foreground()
    draw_adaptive_background()
    print()
    print("次のステップ:")
    print("  cd apps/futa_finance")
    print("  dart run flutter_launcher_icons")
