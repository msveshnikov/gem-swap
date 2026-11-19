"""Google Play store graphics -> renders/play/.

python tools/play_store.py [--no-shots]
  icon_512.png                  app icon
  feature_{ru,en}_1024x500.png  feature graphic: animated world backdrop + gem icon + title
  {ru,en}_N_*.png               phone screenshots 1080x1920 rendered by the game (-- --storeshots)
"""
import glob, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "renders", "play")
RAW = os.path.join(OUT, "raw")
GODOT = os.path.expanduser("~/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe")
TITLE_FONT = os.path.join(ROOT, "assets", "fonts", "Lobster.ttf")
BODY_FONT = os.path.join(ROOT, "assets", "fonts", "Nunito.ttf")


def run(*args):
    subprocess.run([GODOT, "--path", ROOT, *args], check=False, capture_output=True)


def shots():
    for f in glob.glob(os.path.join(RAW, "*_*_*.png")):
        os.remove(f)
    for lang in ("ru", "en"):
        run("--resolution", "576x1024", "--quit-after", "60000", "--", "--storeshots", "--lang", lang)
    for f in sorted(glob.glob(os.path.join(RAW, "*_*_*.png"))):
        im = Image.open(f)
        assert im.size == (576, 1024), (f, im.size)   # the laptop screen is too short for a 1920 px window
        im.convert("RGB").resize((1080, 1920), Image.LANCZOS).save(os.path.join(OUT, os.path.basename(f)))
        print("shot", os.path.basename(f))


def icon():
    Image.open(os.path.join(ROOT, "assets", "ui", "icon_full.png")).convert("RGB").resize((512, 512), Image.LANCZOS) \
        .save(os.path.join(OUT, "icon_512.png"))


def font(path, size, bold=True):
    f = ImageFont.truetype(path, size)
    if bold:
        try:
            f.set_variation_by_axes([850])
        except Exception:
            pass
    return f


def feature(lang):
    w, h = 1024, 500
    p = os.path.join(RAW, "feature_bg.png")
    if not os.path.exists(p):
        run("--resolution", "2048x1000", "--quit-after", "15000", "--", "--featurebg", "--world", "5")
    bg = Image.open(p).convert("RGB").resize((w, h), Image.LANCZOS)
    ic = Image.open(os.path.join(ROOT, "assets", "ui", "icon.png")).convert("RGBA").resize((330, 330), Image.LANCZOS)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((45, 80, 395, 430), 80, fill=(255, 140, 230, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(30))
    bg = bg.convert("RGBA")
    bg.alpha_composite(glow)
    bg.alpha_composite(ic, (55, 85))
    d = ImageDraw.Draw(bg)
    ft = font(TITLE_FONT, 130, False)
    cols = [(255, 45, 85), (255, 138, 28), (255, 213, 31), None, (34, 224, 106), (47, 123, 255), (176, 77, 255), (255, 111, 181)]
    x = 450
    for ch, c in zip("Gem Swap", cols):
        if ch != " ":
            d.text((x, 70), ch, font=ft, fill=c, stroke_width=7, stroke_fill=(25, 5, 40))
        x += d.textlength(ch, font=ft)
    sub = "Меняй. Собирай. Сияй!" if lang == "ru" else "Swap. Match. Sparkle!"
    d.text((456, 255), sub, font=font(BODY_FONT, 40), fill=(255, 240, 220), stroke_width=3, stroke_fill=(20, 8, 40))
    sub2 = "60 уровней · 6 миров · без рекламы" if lang == "ru" else "60 levels · 6 worlds · no ads"
    d.text((458, 320), sub2, font=font(BODY_FONT, 30), fill=(255, 205, 90), stroke_width=3, stroke_fill=(20, 8, 40))
    bg.convert("RGB").save(os.path.join(OUT, f"feature_{lang}_1024x500.png"))
    print("feature", lang)


if __name__ == "__main__":
    os.makedirs(RAW, exist_ok=True)
    icon()
    feature("ru")
    feature("en")
    if "--no-shots" not in sys.argv:
        shots()
