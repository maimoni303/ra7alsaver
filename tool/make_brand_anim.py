"""Animated RA7AL AL3OMR logo (neon heart) -> MP4 + GIF.

    python3 tool/make_brand_anim.py --service TV --out brand_anim

Timeline (4 s loop): the line draws itself into a heart, the dot pops, RA7AL
glows in, AL3OMR types out, the service badge pops, then the heart beats twice.
"""
import argparse
import math
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
BLACK = os.path.join(HERE, "brand_fonts", "Montserrat_900Black.ttf")
BOLD = os.path.join(HERE, "brand_fonts", "Montserrat_700Bold.ttf")  # RA7AL wordmark
LIGHT = os.path.join(HERE, "brand_fonts", "Montserrat_300Light.ttf")

BG = (10, 10, 10)
C0, C1 = (37, 99, 235), (34, 211, 238)  # neon: blue -> cyan
SUB = (186, 230, 253)
BADGE_TXT = (4, 33, 46)
FPS, SECS = 30, 4.0


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def pop(t):
    """0 -> overshoot 1.15 -> 1"""
    t = max(0.0, min(1.0, t))
    if t < 0.6:
        return ease_out(t / 0.6) * 1.15
    return 1.15 - 0.15 * ease_out((t - 0.6) / 0.4)


def beat(t):
    """Two heartbeats between t=0..1 -> scale factor."""
    if t <= 0 or t >= 1:
        return 1.0
    b1 = math.exp(-((t - 0.18) / 0.07) ** 2) * 0.14
    b2 = math.exp(-((t - 0.42) / 0.07) ** 2) * 0.09
    return 1.0 + b1 + b2


def heart_path(x0, x1, y, height, scale=1.0):
    sc = height / 29.0
    cx = (x0 + x1) / 2
    tip = (cx, y)
    pts = [(x0 + (cx - x0) * i / 300, y) for i in range(300)]
    for i in range(1200):
        t = math.pi + 2 * math.pi * i / 1200
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        px, py = cx + hx * sc, (y - 15 * sc) - hy * sc
        # scale the heart around its tip so it stays attached to the line
        pts.append((tip[0] + (px - tip[0]) * scale, tip[1] + (py - tip[1]) * scale))
    pts += [(cx + (x1 - cx) * i / 300, y) for i in range(301)]
    return pts


def text_layer(size, text, font, center, alpha, glow):
    W, H = size
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).text(center, text, font=font, fill=255, anchor="mm")
    bb = mask.getbbox()
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if not bb:
        return out
    g = mask.filter(ImageFilter.GaussianBlur(W * 0.02))
    gl = Image.new("RGBA", size, C1 + (0,))
    gl.putalpha(g.point(lambda v: int(min(255, v * glow * alpha))))
    out = Image.alpha_composite(out, gl)
    grad = Image.new("RGB", size, C0)
    gd = ImageDraw.Draw(grad)
    for x in range(bb[0], bb[2]):
        gd.line([(x, 0), (x, H)], fill=lerp(C0, C1, (x - bb[0]) / max(1, bb[2] - bb[0])))
    lay = grad.convert("RGBA")
    lay.putalpha(mask.point(lambda v: int(v * alpha)))
    return Image.alpha_composite(out, lay)


def frame(t, service, S):
    img = Image.new("RGBA", (S, S), BG + (255,))
    d = ImageDraw.Draw(img)
    # 1) line -> heart -> line drawing itself (0 .. 1.1 s), then beating (2.0 .. 4.0 s)
    draw_p = ease_out(t / 1.1)
    scale = beat((t - 2.0) / 2.0)
    pts = heart_path(S * 0.18, S * 0.82, S * 0.30, S * 0.17, scale)
    n = int(len(pts) * draw_p)
    r = S * 0.011
    glow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for i in range(n):
        px, py = pts[i]
        c = lerp(C0, C1, i / (len(pts) - 1))
        d.ellipse([px - r, py - r, px + r, py + r], fill=c)
        if i % 6 == 0:
            gd.ellipse([px - r * 2.4, py - r * 2.4, px + r * 2.4, py + r * 2.4], fill=c + (70,))
    pulse_glow = 1.0 + (scale - 1.0) * 5
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(S * 0.015))
    glow_layer.putalpha(glow_layer.getchannel("A").point(lambda v: int(min(255, v * pulse_glow))))
    img = Image.alpha_composite(glow_layer, img) if False else Image.alpha_composite(img, glow_layer)
    d = ImageDraw.Draw(img)
    if 0 < n < len(pts):  # bright pen head while drawing
        hx, hy = pts[n - 1]
        d.ellipse([hx - r * 2, hy - r * 2, hx + r * 2, hy + r * 2], fill=(220, 250, 255))
    # 2) dot pops at the end (1.0 .. 1.4 s) and pulses with the beat
    ds = pop((t - 1.0) / 0.4) * (1 + (scale - 1) * 2)
    if ds > 0:
        ex, ey = pts[-1]
        dr = S * 0.026 * ds
        d.ellipse([ex - dr, ey - dr, ex + dr, ey + dr], fill=C1)
    # 3) RA7AL glows in (0.6 .. 1.4 s)
    a = ease_out((t - 0.6) / 0.8)
    if a > 0:
        f = ImageFont.truetype(BOLD, int(S * 0.215))
        y = S * (0.53 + 0.03 * (1 - a))
        img = Image.alpha_composite(img, text_layer((S, S), "RA7AL", f, (S / 2, y), a, 0.9 * pulse_glow))
        d = ImageDraw.Draw(img)
    # 4) AL3OMR types out + underline (1.2 .. 1.8 s)
    fs = ImageFont.truetype(LIGHT, int(S * 0.075))
    sp = S * 0.03
    letters = "AL3OMR"
    total = sum(d.textlength(c, font=fs) for c in letters) + sp * 5
    x = (S - total) / 2
    shown = (t - 1.2) / 0.5 * len(letters)
    for i, ch in enumerate(letters):
        al = max(0.0, min(1.0, shown - i))
        if al > 0:
            d.text((x, S * 0.715), ch, font=fs, fill=SUB + (int(255 * al),), anchor="ls")
        x += d.textlength(ch, font=fs) + sp
    ul = ease_out((t - 1.4) / 0.5)
    if ul > 0:
        x0 = (S - total) / 2
        for xx in range(int(x0), int(x0 + total * ul)):
            d.line([(xx, S * 0.75), (xx, S * 0.757)], fill=lerp(C0, C1, (xx - x0) / total))
    # 5) service badge pops (1.7 .. 2.1 s)
    bs = pop((t - 1.7) / 0.4)
    if bs > 0 and service:
        fb = ImageFont.truetype(BLACK, int(S * 0.07 * bs))
        tw = d.textlength(service, font=fb)
        h = S * 0.11 * bs
        w = tw + S * 0.1 * bs
        cy = S * 0.87
        d.rounded_rectangle([S / 2 - w / 2, cy - h / 2, S / 2 + w / 2, cy + h / 2], radius=h / 2, fill=C1)
        d.text((S / 2, cy), service, font=fb, fill=BADGE_TXT, anchor="mm")
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--service", default="TV")
    ap.add_argument("--out", default="brand_anim")
    ap.add_argument("--size", type=int, default=720)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    tmp = tempfile.mkdtemp()
    S = a.size * 2
    for i in range(int(FPS * SECS)):
        frame(i / FPS, a.service.upper(), S).convert("RGB").resize((a.size, a.size), Image.LANCZOS).save(
            os.path.join(tmp, f"f{i:04d}.png"))
    mp4 = os.path.join(a.out, f"ra7al_{a.service.lower()}_logo.mp4")
    gif = os.path.join(a.out, f"ra7al_{a.service.lower()}_logo.gif")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"),
                    "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-crf", "18", mp4], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf",
                    "fps=20,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", gif], check=True)
    shutil.rmtree(tmp)
    print(mp4, gif)


if __name__ == "__main__":
    main()
