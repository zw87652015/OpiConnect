#!/usr/bin/env python3
# App Store creative generator for OpiLink. Pure PIL, RGB output (no alpha).
# Re-run: python3 appstore/make-creatives.py

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "appstore", "screenshots")
OUT = os.path.join(ROOT, "appstore", "creatives")
ICON = os.path.join(ROOT, "watch", "OpiConnect", "Assets.xcassets",
                    "AppIcon.appiconset", "icon.png")

BG_TOP = (0x1A, 0x1B, 0x2E)
BG_BOT = (0x2B, 0x2D, 0x52)
GLOW = (0x4A, 0x5B, 0xD6)
BEZEL = (0x3A, 0x3C, 0x4E)
BUTTON = (0x2E, 0x30, 0x40)
WHITE = (255, 255, 255)
SUB = (0xB8, 0xBC, 0xE0)

SFNS = "/System/Library/Fonts/SFNS.ttf"
HEITI_MED = "/System/Library/Fonts/STHeiti Medium.ttc"
HEITI_LIGHT = "/System/Library/Fonts/STHeiti Light.ttc"


def en_font(size, bold):
    f = ImageFont.truetype(SFNS, size)
    f.set_variation_by_name("Semibold" if bold else "Regular")
    return f


def zh_font(size, bold):
    path = HEITI_MED if bold else HEITI_LIGHT
    return ImageFont.truetype(path, size, index=1)  # Heiti SC


def is_cjk(ch):
    return ord(ch) > 0x2E7F


def text_width_mixed(latin_font, cjk_font, text):
    return sum(latin_font.getlength(r) if not all(is_cjk(c) for c in r)
               else cjk_font.getlength(r)
               for r in runs(text))


def runs(text):
    out, cur, cjk = [], "", None
    for ch in text:
        c = is_cjk(ch)
        if cjk is None or c == cjk:
            cur += ch
        else:
            out.append(cur)
            cur = ch
        cjk = c
    out.append(cur)
    return out


def draw_mixed(d, x, baseline_y, text, latin_font, cjk_font, fill):
    """Draw text with Latin runs in latin_font and CJK runs in cjk_font,
    sharing a baseline. Returns the total advance width."""
    for r in runs(text):
        f = cjk_font if all(is_cjk(c) for c in r) else latin_font
        d.text((x, baseline_y), r, font=f, fill=fill, anchor="ls")
        x += f.getlength(r)
    return x


def fit_mixed(zh, lines, start, max_w, bold, min_size=20):
    size = start
    while size > min_size:
        lat = zh_font(size, bold) if zh else en_font(size, bold)
        cjk = zh_font(size, bold) if zh else lat
        if all(text_width_mixed(lat, cjk, ln) <= max_w for ln in lines):
            return lat, cjk, size
        size -= 4
    lat = zh_font(min_size, bold) if zh else en_font(min_size, bold)
    return lat, (zh_font(min_size, bold) if zh else lat), min_size


def gradient(w, h, top, bot):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(top, bot))
        for x in range(w):
            px[x, y] = c
    return img


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1],
                                        radius=radius, fill=255)
    return m


def glow_layer(w, h, cx, cy, rw, rh, color, alpha):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - rw / 2, cy - rh / 2, cx + rw / 2, cy + rh / 2],
              fill=color + (round(255 * alpha),))
    return layer.filter(ImageFilter.GaussianBlur(min(w, h) // 6))


def watch_mockup(shot_path, scale):
    """Returns (RGBA image, body_x, body_y, body_w, body_h) — body origin/size
    inside the image, so callers can place watches by body bounds."""
    shot = Image.open(shot_path).convert("RGB")
    sw, sh = round(shot.width * scale), round(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)

    pad = round(sw * 0.06)
    bw, bh = sw + 2 * pad, sh + 2 * pad
    shadow_blur = int(bh * 0.04)
    shadow_dy = int(bh * 0.02)
    margin = shadow_blur + shadow_dy + 40

    W, H = bw + 2 * margin, bh + 2 * margin
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox, oy = margin, margin

    sh_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh_img).rounded_rectangle(
        [ox, oy + shadow_dy, ox + bw, oy + bh + shadow_dy],
        radius=int(bw * 0.22), fill=(0, 0, 0, round(255 * 0.4)))
    img = Image.alpha_composite(img, sh_img.filter(
        ImageFilter.GaussianBlur(shadow_blur)))

    d = ImageDraw.Draw(img)
    d.rounded_rectangle([ox, oy, ox + bw, oy + bh], radius=int(bw * 0.22),
                        fill=(0, 0, 0, 255), outline=BEZEL + (255,),
                        width=max(2, int(bw * 0.015)))
    cw, ch = max(6, int(bw * 0.03)), int(bh * 0.09)
    d.rounded_rectangle([ox + bw - cw // 2, oy + int(bh * 0.25),
                         ox + bw + cw, oy + int(bh * 0.25) + ch],
                        radius=cw, fill=BUTTON + (255,))
    bw2, bh2 = max(4, int(bw * 0.022)), int(bh * 0.14)
    d.rounded_rectangle([ox + bw - bw2 // 2, oy + int(bh * 0.25) + ch + int(bh * 0.03),
                         ox + bw + bw2, oy + int(bh * 0.25) + ch + int(bh * 0.03) + bh2],
                        radius=bw2, fill=BUTTON + (255,))
    screen = Image.new("RGBA", (sw, sh))
    screen.paste(shot, (0, 0))
    img.paste(screen, (ox + pad, oy + pad),
              rounded_mask((sw, sh), int(sw * 0.17)))
    return img, ox, oy, bw, bh


def icon_masked(size):
    icon = Image.open(ICON).convert("RGB").resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size))
    out.paste(icon, (0, 0), rounded_mask((size, size), int(size * 0.22)))
    return out


def shot_path(locale, name):
    return os.path.join(SHOTS, locale, name)


def make_header(locale, heading, subline):
    W, H = 3840, 1646
    img = gradient(W, H, BG_TOP, BG_BOT).convert("RGBA")
    zh = locale == "zh-Hans"

    # two watches side by side in the right ~52%, no overlap
    left_w, lox, loy, lbw, lbh = watch_mockup(shot_path(locale, "01-home.png"), 2.0)
    right_w, rox, roy, rbw, rbh = watch_mockup(shot_path(locale, "03-otp.png"), 2.0)
    gap = 110
    group_w = lbw + gap + rbw
    gx = W - 200 - group_w                     # body left of first watch
    gy = (H - lbh) // 2                        # vertically centered bodies
    group_left = gx

    img = Image.alpha_composite(img, glow_layer(
        W, H, int(gx + group_w / 2), int(gy + lbh / 2),
        group_w * 1.35, H * 1.5, GLOW, 0.25))

    # text block, vertically centered in left region
    x0 = 260
    max_w = group_left - x0 - 80
    head_lat, head_cjk, head_size = fit_mixed(
        zh, heading.split("\n"), 150, max_w, bold=True)
    sub_lat, sub_cjk, sub_size = fit_mixed(
        zh, [subline], 64, max_w, bold=False)
    icon_s = 200
    lh = round(head_size * 1.12)
    block_h = (icon_s + 50 + lh * len(heading.split("\n")) + 40
               + round(sub_size * 1.3))
    ty = (H - block_h) // 2
    icon = icon_masked(icon_s)
    img.paste(icon, (x0, ty), icon)
    ty += icon_s + 50
    d = ImageDraw.Draw(img)
    for ln in heading.split("\n"):
        draw_mixed(d, x0, ty + head_size, ln, head_lat, head_cjk, WHITE)
        ty += lh
    ty += 40
    draw_mixed(d, x0, ty + sub_size, subline, sub_lat, sub_cjk, SUB)

    img.alpha_composite(left_w, (int(gx - lox), int(gy - loy)))
    img.alpha_composite(right_w, (int(gx + lbw + gap - rox), int(gy - roy)))

    out_dir = os.path.join(OUT, locale)
    os.makedirs(out_dir, exist_ok=True)
    img.convert("RGB").save(os.path.join(out_dir, "header.png"))


def make_search(locale, heading, subline):
    W, H = 3840, 2560
    img = gradient(W, H, BG_TOP, BG_BOT).convert("RGBA")
    zh = locale == "zh-Hans"

    head_lat, head_cjk, head_size = fit_mixed(zh, [heading], 170, W - 400, True)
    sub_lat, sub_cjk, sub_size = fit_mixed(zh, [subline], 70, W - 400, False)

    d = ImageDraw.Draw(img)
    ty = 220
    w = text_width_mixed(head_lat, head_cjk, heading)
    draw_mixed(d, (W - w) / 2, ty + head_size, heading, head_lat, head_cjk, WHITE)
    ty += round(head_size * 1.2) + 50
    w = text_width_mixed(sub_lat, sub_cjk, subline)
    draw_mixed(d, (W - w) / 2, ty + sub_size, subline, sub_lat, sub_cjk, SUB)

    # three watches, no overlap: ~140px gap between bodies, >=180px side margins
    scale = 2.2
    gap = 140
    names = ["01-home.png", "02-detail.png", "03-otp.png"]
    watches = [watch_mockup(shot_path(locale, n), scale) for n in names]
    bw = watches[0][3]
    total = 3 * bw + 2 * gap
    x_body = (W - total) / 2
    bh = max(w[4] for w in watches)
    # row slightly below vertical center, >=160px bottom margin (to body bottom)
    y_body = H - 160 - bh - (H - 160 - bh - (ty + 120)) // 3

    img = Image.alpha_composite(img, glow_layer(
        W, H, W // 2, int(y_body + bh / 2), total * 1.15, bh * 1.8, GLOW, 0.25))
    for w_img, ox, oy, wb, hb in watches:
        img.alpha_composite(w_img, (round(x_body - ox), round(y_body - oy)))
        x_body += wb + gap

    out_dir = os.path.join(OUT, locale)
    os.makedirs(out_dir, exist_ok=True)
    img.convert("RGB").save(os.path.join(out_dir, "search.png"))


if __name__ == "__main__":
    make_header("en-US",
                "Your Android notifications,\non your wrist.",
                "End-to-end encrypted · Replies · Find My Phone · Calendar")
    make_header("zh-Hans",
                "安卓手机通知，\n戴在手腕上。",
                "端到端加密 · 快捷回复 · 查找手机 · 日历同步")
    make_search("en-US",
                "Android notifications on Apple Watch",
                "Reply, dismiss, find your phone — end-to-end encrypted.")
    make_search("zh-Hans",
                "在 Apple Watch 上收安卓通知",
                "回复、清除、查找手机，全程端到端加密。")
    print("done")
