"""Draw the AgentUsageBar app icon (gauge on dark squircle) and build AppIcon.icns."""
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersample, downscaled for each size
here = os.path.dirname(os.path.abspath(__file__))

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def draw():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = int(S * 0.098)  # macOS icon grid margin
    box = (m, m, S - m, S - m)
    top, bot = (38, 44, 70), (14, 17, 32)
    grad = Image.linear_gradient("L").resize((S, S))
    bg = Image.composite(Image.new("RGBA", (S, S), bot + (255,)), Image.new("RGBA", (S, S), top + (255,)), grad)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=int((S - 2 * m) * 0.225), fill=255)
    img.paste(bg, (0, 0), mask)

    ov = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    cx, cy, R, w = S / 2, S * 0.56, S * 0.30, S * 0.075
    # track
    tl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(tl).arc((cx - R, cy - R, cx + R, cy + R), 150, 390, fill=(255, 255, 255, 40), width=int(w))
    img = Image.alpha_composite(img, tl)
    # value arc, cyan -> lime, ~67%
    a0, a1 = 150, 150 + 240 * 0.67
    n = 120
    for i in range(n):
        t = i / n
        a = a0 + (a1 - a0) * t
        b = a0 + (a1 - a0) * (i + 1.6) / n
        d.arc((cx - R, cy - R, cx + R, cy + R), a, b, fill=lerp((56, 200, 255), (170, 230, 80), t) + (255,), width=int(w))
    # round caps
    for ang, t in ((a0, 0), (a1, 1)):
        r = math.radians(ang)
        x, y = cx + R * math.cos(r), cy + R * math.sin(r)
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=lerp((56, 200, 255), (170, 230, 80), t) + (255,))
    # ticks
    for i in range(0, 13):
        r = math.radians(150 + 240 * i / 12)
        r0, r1 = R - w * 1.1, R - w * (1.6 if i % 3 else 2.1)
        d.line((cx + r0 * math.cos(r), cy + r0 * math.sin(r), cx + r1 * math.cos(r), cy + r1 * math.sin(r)), fill=(190, 198, 220, 255), width=int(S * 0.008))
    # needle
    r = math.radians(a1)
    L = R * 0.78
    d.line((cx, cy, cx + L * math.cos(r), cy + L * math.sin(r)), fill=(255, 255, 255, 255), width=int(S * 0.026))
    hub = S * 0.045
    d.ellipse((cx - hub, cy - hub, cx + hub, cy + hub), fill=(255, 255, 255, 255))
    d.ellipse((cx - hub * 0.45, cy - hub * 0.45, cx + hub * 0.45, cy + hub * 0.45), fill=(14, 17, 32, 255))
    img = Image.alpha_composite(img, ov)
    return img

big = draw()
iconset = os.path.join(here, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
for base in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        px = base * sc
        big.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, f"icon_{base}x{base}{'@2x' if sc == 2 else ''}.png"))
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(here, "AppIcon.icns")], check=True)
big.resize((1024, 1024), Image.LANCZOS).save(os.path.join(here, "AppIcon_1024.png"))
print("ok")
