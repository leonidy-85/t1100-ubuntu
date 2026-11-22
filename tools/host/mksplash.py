#!/usr/bin/env python3
"""Compose the T1100 boot splash for landscape use.

The panel scans out 1600x2176 (portrait).  The scene is composed in
landscape (2176x1600) and then rotated 90 degrees to the right, so it
looks upright when the tablet is held horizontally.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

FW, FH = 1600, 2176      # framebuffer
W, H = 2176, 1600        # landscape scene
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def background():
    img = Image.new("RGB", (W, H), (0, 0, 0))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        r = int(12 + 10 * (1 - t))
        g = int(18 + 16 * (1 - t))
        b = int(28 + 30 * (1 - t))
        for x in range(W):
            px[x, y] = (r, g, b)
    return img


def text(draw, s, y, fill, size=118):
    f = ImageFont.truetype(FONT, size)
    w = draw.textbbox((0, 0), s, font=f)[2]
    draw.text(((W - w) // 2, y), s, font=f, fill=fill)


def main(src, out):
    img = background()
    tux = Image.open(src).convert("RGBA")
    # landscape: penguin above the caption
    scale = min(800 / tux.width, 960 / tux.height)
    tux = tux.resize((int(tux.width * scale), int(tux.height * scale)),
                     Image.LANCZOS)
    x = (W - tux.width) // 2
    y = 70
    img.paste(tux, (x, y), tux)

    draw = ImageDraw.Draw(img)
    text(draw, "работает на всём,", 1090, (245, 245, 245))
    f = ImageFont.truetype(FONT, 118)
    left = "даже на "
    wl = draw.textbbox((0, 0), left, font=f)[2]
    wr = draw.textbbox((0, 0), "MTK", font=f)[2]
    x0 = (W - (wl + wr)) // 2
    draw.text((x0, 1245), left, font=f, fill=(245, 245, 245))
    draw.text((x0 + wl, 1245), "MTK", font=f, fill=(126, 231, 144))

    # rotate clockwise so the scene is upright in the portrait framebuffer
    img = img.rotate(-90, expand=True)
    assert img.size == (FW, FH), img.size
    img.save(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
