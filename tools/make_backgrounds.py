"""Painted backgrounds: art/bg_raw/<name>.png (ChatGPT, 1024x1536) -> assets/bg/<name>.jpg (768x1152).

Afterwards run a headless --import once, then this script with --patch-import: it switches every background to lossy
WebP with mipmaps (the shader blurs with textureLod) and Godot re-imports them on the next --import.
Prompts: art/bg_prompts.json.
"""
import glob
import os
import re
import sys

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art", "bg_raw")
OUT = os.path.join(ROOT, "assets", "bg")
SIZE = (768, 1152)


def convert() -> None:
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for p in sorted(glob.glob(os.path.join(RAW, "*.png"))):
        name = os.path.splitext(os.path.basename(p))[0]
        im = Image.open(p).convert("RGB")
        if im.size != SIZE:
            # 2:3 crop first if the source is not 2:3
            w, h = im.size
            if abs(w / h - 2 / 3) > 0.01:
                if w / h > 2 / 3:
                    nw = int(h * 2 / 3)
                    im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
                else:
                    nh = int(w * 3 / 2)
                    im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
            im = im.resize(SIZE, Image.LANCZOS)
        im = ImageEnhance.Contrast(im).enhance(1.03)
        im.save(os.path.join(OUT, name + ".jpg"), quality=86, optimize=True, progressive=False)
        n += 1
    print("backgrounds:", n)


def patch_import() -> None:
    n = 0
    for p in glob.glob(os.path.join(OUT, "*.jpg.import")):
        s = open(p, encoding="utf-8").read()
        s2 = re.sub(r"compress/mode=\d+", "compress/mode=1", s)
        s2 = re.sub(r"compress/lossy_quality=[\d.]+", "compress/lossy_quality=0.8", s2)
        s2 = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", s2)
        if s2 != s:
            open(p, "w", encoding="utf-8").write(s2)
            n += 1
    print("patched:", n)


if __name__ == "__main__":
    if "--patch-import" in sys.argv:
        patch_import()
    else:
        convert()
