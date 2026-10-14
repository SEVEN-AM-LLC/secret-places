#!/usr/bin/env python3
"""Builds App Store screenshots (6.9", 1320x2868) from raw simulator captures.

Raw captures: appstore/raw/NN-name.png, taken on iPhone 17 Pro Max with the status bar
overridden to 9:41 (`xcrun simctl status_bar ... override --time 9:41`).
Output: appstore/<locale>/NN-name.png
Run: python3 appstore/compose.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
W, H = 1320, 2868
BG_TOP, BG_BOTTOM = (30, 30, 40), (13, 13, 17)
GOLD, TEXT, MUTED = (217, 184, 107), (244, 242, 238), (166, 166, 173)
SF = "/System/Library/Fonts/SFNS.ttf"

CAPTIONS = {
    "en-US": {
        "01-discover": ("The city's best-kept secrets", "Hidden bars, quiet viewpoints and underground nights, curated by locals."),
        "02-locked":   ("Secrets stay secret", "See the vibe and the rough area. Unlock the exact spot when you're ready."),
        "03-map":      ("The hidden city, mapped", "Free spots in green. Locked ones only show an approximate area."),
        "04-unlocked": ("Get the door word", "The exact spot, directions and the password to get in."),
        "05-route":    ("Follow a night route", "Self-guided crawls: every unmarked door, in order."),
    },
}


def font(size: int, weight: bytes) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=f) <= width:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    return lines + [cur]


def background() -> Image.Image:
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3)))
    # soft gold glow behind the headline, echoing the app icon
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.1, -H * 0.08, W * 0.9, H * 0.22], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    return Image.composite(Image.new("RGB", (W, H), GOLD), img, glow.point(lambda v: v * 0.35))


def compose(raw: Path, title: str, subtitle: str) -> Image.Image:
    img = background()
    d = ImageDraw.Draw(img)
    margin = 96
    f_title, f_sub = font(104, b"Bold"), font(50, b"Regular")
    y = 190
    for line in wrap(d, title, f_title, W - 2 * margin):
        d.text((W / 2, y), line, font=f_title, fill=TEXT, anchor="mt")
        y += 120
    y += 22
    for line in wrap(d, subtitle, f_sub, W - 2 * margin - 40):
        d.text((W / 2, y), line, font=f_sub, fill=MUTED, anchor="mt")
        y += 66

    # device screen: scaled, rounded, with a thin bezel; bleeds off the bottom edge
    shot = Image.open(raw).convert("RGB")
    sw = int(W * 0.80)
    shot = shot.resize((sw, int(shot.height * sw / shot.width)), Image.LANCZOS)
    top = max(y + 80, 700)
    radius, bezel = 96, 14
    frame = Image.new("RGBA", (sw + 2 * bezel, shot.height + 2 * bezel), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([0, 0, frame.width - 1, frame.height - 1], radius + bezel, fill=(52, 52, 62, 255))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius, fill=255)
    frame.paste(shot, (bezel, bezel), mask)

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x0 = (W - frame.width) // 2
    ImageDraw.Draw(shadow).rounded_rectangle([x0, top + 30, x0 + frame.width, top + 30 + frame.height], radius, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    img = Image.alpha_composite(img.convert("RGBA"), shadow)
    img.alpha_composite(frame, (x0, top))
    return img.convert("RGB")  # App Store rejects alpha channels


if __name__ == "__main__":
    for locale, caps in CAPTIONS.items():
        out = HERE / locale
        out.mkdir(exist_ok=True)
        for name, (title, subtitle) in caps.items():
            compose(HERE / "raw" / f"{name}.png", title, subtitle).save(out / f"{name}.png", optimize=True)
            print(f"{locale}/{name}.png")
