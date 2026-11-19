"""App icon (512) and boot splash from the rendered gem strips. python tools/make_icon.py"""
from PIL import Image, ImageDraw, ImageFilter
import os, math
R = os.path.join(os.path.dirname(__file__), "..")
def frame(name, f=2):
    s = Image.open(os.path.join(R, "assets/gems/%s.png" % name)).convert("RGBA")
    h = s.height
    return s.crop((f * h, 0, f * h + h, h))
def cluster(size):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((size * 0.18, size * 0.18, size * 0.82, size * 0.82), fill=(255, 220, 255, 170))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    im.alpha_composite(glow)
    items = [("sapphire", -0.24, 0.20, 0.40, 1), ("emerald", 0.25, 0.20, 0.40, 3), ("ruby", -0.24, -0.20, 0.40, 5),
             ("citrine", 0.24, -0.22, 0.40, 6), ("diamond", 0.0, 0.0, 0.62, 2)]
    for n, dx, dy, sc, f in items:
        g = frame(n, f).resize((int(size * sc), int(size * sc)), Image.LANCZOS)
        sh = Image.new("RGBA", g.size, (0, 0, 0, 0)); sh.putalpha(g.getchannel("A").point(lambda a: int(a * 0.45)))
        x = int(size * (0.5 + dx) - g.width / 2); y = int(size * (0.5 + dy) - g.height / 2)
        im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)), (x + 5, y + 9))
        im.alpha_composite(g, (x, y))
    return im
S = 512
bg = Image.new("RGBA", (S, S))
px = bg.load()
for y in range(S):
    for x in range(S):
        d = math.hypot(x - S * 0.5, y - S * 0.45) / (S * 0.75)
        t = min(1, d)
        px[x, y] = (int(120 * (1 - t) + 25 * t), int(40 * (1 - t) + 8 * t), int(190 * (1 - t) + 60 * t), 255)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=110, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(bg, (0, 0), mask)
icon.alpha_composite(cluster(S))
os.makedirs(os.path.join(R, "assets/ui"), exist_ok=True)
icon.save(os.path.join(R, "assets/ui/icon.png"))
full = bg.copy(); full.alpha_composite(cluster(S)); full.convert("RGB").save(os.path.join(R, "assets/ui/icon_full.png"))
cluster(400).save(os.path.join(R, "assets/ui/splash.png"))
print("ok")

# platform icon variants
icon.resize((192, 192), Image.LANCZOS).save(os.path.join(R, "assets/ui/icon_192.png"))
icon.save(os.path.join(R, "assets/ui/icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
A = 432
fg = Image.new("RGBA", (A, A), (0, 0, 0, 0))
c = cluster(int(A * 0.66))
fg.alpha_composite(c, ((A - c.width) // 2, (A - c.height) // 2))
fg.save(os.path.join(R, "assets/ui/adaptive_fg_432.png"))
bg.resize((A, A), Image.LANCZOS).convert("RGB").save(os.path.join(R, "assets/ui/adaptive_bg_432.png"))
print("icons ok")
