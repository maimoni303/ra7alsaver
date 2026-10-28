"""RA7AL AL3OMR brand generator — one look for every app, with a service label.

Usage:
    python3 tool/make_brand.py --service TV --out assets

Writes:
    icon.png       1024x1024 app icon (iOS, Android, macOS, Windows)
    tv_banner.png  320x180 Android TV launcher banner
    logo_wide.png  1200x420 horizontal logo used inside the app

Change --service for future products (e.g. "NAS", "CUSTODY").
Fonts: Montserrat (SIL Open Font License), bundled in tool/brand_fonts.
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
BLACK = os.path.join(HERE, "brand_fonts", "Montserrat_900Black.ttf")
BOLD = os.path.join(HERE, "brand_fonts", "Montserrat_700Bold.ttf")  # RA7AL wordmark
LIGHT = os.path.join(HERE, "brand_fonts", "Montserrat_300Light.ttf")

BG = (10, 10, 10)
DARK_BLUE = (24, 44, 92)      # start of the RA7AL gradient (kept visible at small sizes)
BRIGHT_BLUE = (59, 130, 246)  # end of the gradient, dot, badge
SUB_GREY = (138, 154, 181)


STYLES = {
    # name: (text gradient stops, wave start, wave end, dot/badge, badge text, glow strength, sub text)
    "classic":  ([(24, 44, 92), (59, 130, 246)], (20, 34, 70), (40, 80, 160), (59, 130, 246), (255, 255, 255), 0.45, (138, 154, 181)),
    "neon":     ([(37, 99, 235), (34, 211, 238)], (30, 64, 175), (34, 211, 238), (34, 211, 238), (4, 33, 46), 0.85, (186, 230, 253)),
    "vibe":     ([(59, 130, 246), (139, 92, 246), (236, 72, 153)], (59, 130, 246), (236, 72, 153), (236, 72, 153), (255, 255, 255), 0.75, (221, 214, 254)),
    "electric": ([(59, 130, 246), (45, 212, 191)], (59, 130, 246), (163, 230, 53), (163, 230, 53), (20, 35, 5), 0.7, (204, 251, 241)),
}
STYLE = STYLES["classic"]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def lerp_stops(stops, t):
    if len(stops) == 2:
        return lerp(stops[0], stops[1], t)
    seg = min(int(t * (len(stops) - 1)), len(stops) - 2)
    local = t * (len(stops) - 1) - seg
    return lerp(stops[seg], stops[seg + 1], local)


def gradient_text(size, text, font, x, y, c0, c1, glow=True):
    """Returns an RGBA layer with horizontally graded text (+ soft glow)."""
    W, H = size
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255, anchor="lm")
    bbox = mask.getbbox() or (0, 0, W, H)
    grad = Image.new("RGB", size, c0)
    gd = ImageDraw.Draw(grad)
    x0, x1 = bbox[0], max(bbox[2], bbox[0] + 1)
    for xx in range(x0, x1):
        gd.line([(xx, 0), (xx, H)], fill=lerp_stops(STYLE[0], (xx - x0) / (x1 - x0)))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    if glow:
        g = mask.filter(ImageFilter.GaussianBlur(max(4, H // 40)))
        glow_layer = Image.new("RGBA", size, STYLE[3] + (0,))
        glow_layer.putalpha(g.point(lambda v: int(min(255, v * STYLE[5]))))
        layer = Image.alpha_composite(layer, glow_layer)
    text_layer = grad.convert("RGBA")
    text_layer.putalpha(mask)
    return Image.alpha_composite(layer, text_layer), bbox


def spaced_text(draw, x, y, text, font, fill, spacing):
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill, anchor="ls")
        x += draw.textlength(ch, font=font) + spacing
    return x - spacing


def spaced_width(draw, text, font, spacing):
    return sum(draw.textlength(ch, font=font) for ch in text) + spacing * (len(text) - 1)


WAVE = "sine"


def heart_line(draw, x0, x1, y, height, width, dot_r):
    """Line -> heart -> line, drawn as one continuous stroke (tip of the heart on the line)."""
    sc = height / 29.0
    cx = (x0 + x1) / 2
    cy = y - 15 * sc  # heart bottom tip (param y = -15) sits on the baseline

    def hp(t):
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        return cx + hx * sc, cy - hy * sc

    pts = []
    for i in range(300):
        pts.append((x0 + (cx - x0) * i / 300, y))
    for i in range(1200):
        t = math.pi + math.pi * 2 * i / 1200  # pi -> 3pi: left lobe, notch, right lobe
        pts.append(hp(t))
    for i in range(301):
        pts.append((cx + (x1 - cx) * i / 300, y))
    r = width / 2
    n = len(pts)
    for i, (px, py) in enumerate(pts):
        draw.ellipse([px - r, py - r, px + r, py + r], fill=lerp(STYLE[1], STYLE[2], i / (n - 1)))
    ex, ey = pts[-1]
    draw.ellipse([ex - dot_r, ey - dot_r, ex + dot_r, ey + dot_r], fill=STYLE[3])


def wave(draw, x0, x1, y, amp, width, dot_r):
    if WAVE == "heart":
        return heart_line(draw, x0, x1, y + amp * 1.4, amp * 3.6, width, dot_r)
    pts = []
    n = 400
    for i in range(n + 1):
        t = i / n
        pts.append((x0 + (x1 - x0) * t, y - amp * math.sin(t * 2 * math.pi * 0.95 + 0.25)))
    r = width / 2
    # dense round "brush" stamps give a smooth, evenly thick stroke
    steps = n * 4
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        yy = y - amp * math.sin(t * 2 * math.pi * 0.95 + 0.25)
        draw.ellipse([x - r, yy - r, x + r, yy + r], fill=lerp(STYLE[1], STYLE[2], t))
    dp = pts[int(n * 0.47)]
    draw.ellipse([dp[0] - dot_r, dp[1] - dot_r, dp[0] + dot_r, dp[1] + dot_r], fill=STYLE[3])


def badge(img, cx, cy, text, font, pad_x, pad_y):
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=font)
    asc, desc = font.getmetrics()
    h = asc + pad_y * 2
    w = tw + pad_x * 2
    d.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], radius=h / 2, fill=STYLE[3])
    d.text((cx, cy), text, font=font, fill=STYLE[4], anchor="mm")


def make_icon(service, path, S=1024, K=2):
    W = S * K
    img = Image.new("RGBA", (W, W), BG + (255,))
    d = ImageDraw.Draw(img)
    wave(d, W * 0.20, W * 0.80, W * 0.25, W * 0.045, int(W * 0.018), W * 0.022)
    f_big = ImageFont.truetype(BOLD, int(W * 0.215))
    layer, bbox = gradient_text((W, W), "RA7AL", f_big, 0, int(W * 0.47), DARK_BLUE, BRIGHT_BLUE)
    tw = bbox[2] - bbox[0]
    shifted = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shifted.paste(layer, (int((W - tw) / 2 - bbox[0]), 0), layer)
    img = Image.alpha_composite(img, shifted)
    d = ImageDraw.Draw(img)
    f_sub = ImageFont.truetype(LIGHT, int(W * 0.075))
    sp = W * 0.03
    sw = spaced_width(d, "AL3OMR", f_sub, sp)
    spaced_text(d, (W - sw) / 2, W * 0.665, "AL3OMR", f_sub, STYLE[6], sp)
    ul_y, ul_h = W * 0.70, max(4, int(W * 0.007))
    for xx in range(int((W - sw) / 2), int((W + sw) / 2)):
        t = (xx - (W - sw) / 2) / sw
        d.line([(xx, ul_y), (xx, ul_y + ul_h)], fill=lerp_stops(STYLE[0], t))
    if service:
        f_badge = ImageFont.truetype(BLACK, int(W * 0.07))
        badge(img, W / 2, W * 0.835, service.upper(), f_badge, int(W * 0.05), int(W * 0.02))
    img.convert("RGB").resize((S, S), Image.LANCZOS).save(path)


def make_wide(service, path, size, K=3, badge_on=True):
    w, h = size
    W, H = w * K, h * K
    img = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(img)
    wave(d, W * 0.03, W * 0.30, H * 0.47, H * 0.09, max(3, int(H * 0.018)), H * 0.03)
    f_big = ImageFont.truetype(BOLD, int(H * 0.30))
    layer, bbox = gradient_text((W, H), "RA7AL", f_big, int(W * 0.37), int(H * 0.40), DARK_BLUE, BRIGHT_BLUE)
    img = Image.alpha_composite(img, layer)
    d = ImageDraw.Draw(img)
    f_sub = ImageFont.truetype(LIGHT, int(H * 0.11))
    sp = H * 0.045
    x0 = bbox[0]
    x_end = spaced_text(d, x0, H * 0.73, "AL3OMR", f_sub, STYLE[6], sp)
    ul_y = H * 0.79
    for xx in range(int(x0), int(x_end)):
        t = (xx - x0) / max(1, x_end - x0)
        d.line([(xx, ul_y), (xx, ul_y + max(2, H * 0.008))], fill=lerp_stops(STYLE[0], t))
    if service and badge_on:
        f_badge = ImageFont.truetype(BLACK, int(H * 0.10))
        bw = d.textlength(service.upper(), font=f_badge) + H * 0.10
        badge(img, x_end + H * 0.08 + bw / 2, H * 0.70, service.upper(), f_badge, int(H * 0.05), int(H * 0.025))
    img.convert("RGB").resize((w, h), Image.LANCZOS).save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--service", default="TV")
    ap.add_argument("--out", default="assets")
    ap.add_argument("--style", default="neon", choices=sorted(STYLES))
    ap.add_argument("--wave", default="heart", choices=["sine", "heart"])
    a = ap.parse_args()
    STYLE = STYLES[a.style]
    WAVE = a.wave
    os.makedirs(a.out, exist_ok=True)
    make_icon(a.service, os.path.join(a.out, "icon.png"))
    make_wide(a.service, os.path.join(a.out, "tv_banner.png"), (320, 180))
    make_wide(a.service, os.path.join(a.out, "logo_wide.png"), (1200, 420))
    print("done:", a.service)
