"""Generate the original Wallpaper Desk artwork without external assets."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1440, 900
base = Image.new("RGB", (WIDTH, HEIGHT))
rows = ImageDraw.Draw(base)
top, bottom = (245, 240, 231), (217, 230, 223)
for y in range(HEIGHT):
    t = y / (HEIGHT - 1)
    rows.line((0, y, WIDTH, y), fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

light = Image.new("RGBA", base.size)
shapes = ImageDraw.Draw(light)
shapes.ellipse((780, -310, 1550, 430), fill=(227, 167, 113, 130))
shapes.ellipse((1050, 75, 1670, 705), fill=(223, 138, 118, 80))
shapes.ellipse((280, 330, 1470, 1170), fill=(112, 171, 157, 105))
base = Image.alpha_composite(base.convert("RGBA"), light.filter(ImageFilter.GaussianBlur(130)))

arcs = Image.new("RGBA", base.size)
ink = ImageDraw.Draw(arcs)
for i in range(8):
    offset = 25 * i
    ink.arc((555 + offset, 115 + offset, 1620 - offset, 1175 - offset),
            start=172, end=305, fill=(255, 250, 240, 112 - i * 8), width=2)
base = Image.alpha_composite(base, arcs)
base.convert("RGB").save(Path(__file__).with_name("default-wallpaper.png"), optimize=True)
