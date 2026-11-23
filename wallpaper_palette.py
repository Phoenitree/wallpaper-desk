import argparse
import colorsys
import json
import os
import pathlib
import re
import tempfile
import tomllib

from PIL import Image, ImageOps


def mix(a, b, weight):
    return tuple(round(x * (1 - weight) + y * weight) for x, y in zip(a, b))


def hex_rgb(rgb):
    return "#" + "".join(f"{n:02x}" for n in rgb)


def luminance(rgb):
    channels = [n / 255 for n in rgb]
    linear = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in channels]
    return sum(a * b for a, b in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    low, high = sorted((luminance(a), luminance(b)))
    return (high + 0.05) / (low + 0.05)


def extract(path, mode):
    with Image.open(path) as source:
        thumb = ImageOps.exif_transpose(source)
        thumb.thumbnail((90, 90), Image.Resampling.LANCZOS)
        rgba = thumb.convert("RGBA")
    paper = Image.new("RGBA", rgba.size, "#f7f6f5")
    pixels = Image.alpha_composite(paper, rgba).convert("RGB")
    mean = pixels.resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
    quantized = pixels.quantize(colors=14)
    swatches = quantized.getpalette()
    samples = [(count, tuple(swatches[index * 3:index * 3 + 3]))
               for count, index in quantized.getcolors()]

    def rank(sample):
        count, rgb = sample
        _, saturation, value = colorsys.rgb_to_hsv(*(n / 255 for n in rgb))
        return count ** 0.42 * saturation * min(value * 2, 1) * (1 - 0.65 * max(0, value - 0.8))

    hue = max(samples, key=rank)[1]
    dark = mode == "dark"
    base = mix((26, 26, 29) if dark else (250, 250, 249), mean, 0.14 if dark else 0.15)
    panel = mix(base, (255, 255, 255), 0.06 if dark else 0.45)
    text = mix((247, 248, 247) if dark else (24, 25, 27), hue, 0.09)
    accent = hue
    for _ in range(20):
        if contrast(accent, base) >= 4.5:
            break
        accent = mix(accent, (255, 255, 255) if dark else (0, 0, 0), 0.17)
    return {key: hex_rgb(rgb) for key, rgb in
            dict(accent=accent, background=base, foreground=text, panel=panel).items()}


def sync(path, mode, palette):
    if any(not re.fullmatch(r"#[a-fA-F0-9]{6}", palette.get(k, "")) for k in ("accent", "background", "foreground")):
        raise ValueError("Invalid wallpaper palette")
    key = f"appearance{mode.title()}ChromeTheme"
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig")
    config = tomllib.loads(text)
    eol = "\r\n" if "\r\n" in text else "\n"
    section = re.compile(rf"(?m)^\[desktop\.{key}[ \t]*\][ \t]*(?:#[^\r\n]*)?\r?\n")
    header = section.search(text)
    values = dict(accent=palette["accent"], accentSource="custom",
                  surface=palette["background"], ink=palette["foreground"])
    if header:
        tail = re.search(r"(?m)^\[", text[header.end():])
        end = header.end() + tail.start() if tail else len(text)
        block = text[header.end():end]
        for field, value in values.items():
            row = re.compile(rf'(?m)^({field}[ \t]*=[ \t]*)"(?:\\.|[^"\\\r\n])*"')
            if row.search(block):
                block = row.sub(lambda m: f'{m[1]}"{value}"', block, count=1)
            else:
                block = f'{field} = "{value}"{eol}' + block
        updated = text[:header.end()] + block + text[end:]
    elif key not in config.get("desktop", {}):
        updated = text.rstrip("\r\n") + eol * 2 + f"[desktop.{key}]" + eol
        updated += "".join(f'{field} = "{value}"{eol}' for field, value in values.items())
    else:
        raise ValueError("Codex theme uses an inline table; wallpaper still works in the active window.")
    parsed = tomllib.loads(updated)["desktop"][key]
    if any(parsed.get(field) != val for field, val in values.items()):
        raise ValueError("Codex appearance settings could not be verified")
    if updated == text:
        return
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix="asuka-palette-", delete=False) as out:
        temp = pathlib.Path(out.name)
        out.write(updated.encode("utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8"))
    try:
        if path.read_bytes() != raw:
            raise RuntimeError("Codex updated settings at the same time; retry Apply.")
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    photo = commands.add_parser("extract")
    photo.add_argument("image", type=pathlib.Path)
    photo.add_argument("mode", choices=("light", "dark"))
    settings = commands.add_parser("sync")
    settings.add_argument("config", type=pathlib.Path)
    settings.add_argument("mode", choices=("light", "dark"))
    settings.add_argument("accent")
    settings.add_argument("background")
    settings.add_argument("foreground")
    args = parser.parse_args()
    if args.command == "extract":
        print(json.dumps(extract(args.image, args.mode)))
    else:
        sync(args.config, args.mode, vars(args))


if __name__ == "__main__":
    main()
