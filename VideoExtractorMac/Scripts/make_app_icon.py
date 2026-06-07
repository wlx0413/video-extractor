from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "Build" / "IconBuild" / "AppIcon.iconset"
ICONSET.mkdir(parents=True, exist_ok=True)


def gradient(size, left=(67, 138, 255), right=(235, 95, 204)):
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x * 0.72 + y * 0.28) / size
            r = int(left[0] * (1 - t) + right[0] * t)
            g = int(left[1] * (1 - t) + right[1] * t)
            b = int(left[2] * (1 - t) + right[2] * t)
            pixels[x, y] = (r, g, b, 255)
    return image


def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def stroke_mask(size, rect, radius, width, gap_bottom=True):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(rect, radius=radius, outline=255, width=width)

    if gap_bottom:
        x1, y1, x2, y2 = rect
        clear = ImageDraw.Draw(mask)
        clear.rounded_rectangle(
            (x1 + width * 2.5, y2 - width * 1.4, x1 + width * 7.5, y2 + width * 1.4),
            radius=width,
            fill=0,
        )
        clear.rounded_rectangle(
            (x2 - width * 7.5, y2 - width * 1.4, x2 - width * 2.5, y2 + width * 1.4),
            radius=width,
            fill=0,
        )
    return mask


def triangle_mask(size):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    points = [
        (int(size * 0.372), int(size * 0.343)),
        (int(size * 0.372), int(size * 0.642)),
        (int(size * 0.628), int(size * 0.492)),
    ]
    draw.polygon(points, fill=255)
    return mask


def arrow_mask(size):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    w = int(size * 0.052)
    cx = int(size * 0.50)
    top = int(size * 0.655)
    bottom = int(size * 0.827)
    head_y = int(size * 0.760)
    head_w = int(size * 0.095)
    draw.rounded_rectangle((cx - w // 2, top, cx + w // 2, bottom - int(size * 0.050)), radius=w // 2, fill=255)
    draw.line((cx - head_w, head_y, cx, bottom, cx + head_w, head_y), fill=255, width=w, joint="curve")
    return mask


def make_icon(size):
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_mask = rounded_rect_mask(size, int(size * 0.205))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.bitmap((0, int(size * 0.018)), shadow_mask, fill=(95, 99, 124, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(size * 0.028)))
    canvas.alpha_composite(shadow)

    base = Image.new("RGBA", (size, size), (250, 250, 252, 255))
    base_overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(base_overlay)
    overlay_draw.ellipse(
        (int(size * 0.09), int(size * 0.62), int(size * 0.91), int(size * 1.13)),
        fill=(110, 118, 255, 28),
    )
    base = Image.alpha_composite(base, base_overlay.filter(ImageFilter.GaussianBlur(int(size * 0.055))))
    base.putalpha(rounded_rect_mask(size, int(size * 0.205)))
    canvas.alpha_composite(base)

    grad = gradient(size)

    frame = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    frame_mask = stroke_mask(
        size,
        (
            int(size * 0.195),
            int(size * 0.230),
            int(size * 0.805),
            int(size * 0.785),
        ),
        radius=int(size * 0.155),
        width=max(5, int(52 * scale)),
    )
    frame.alpha_composite(grad)
    frame.putalpha(frame_mask)
    canvas.alpha_composite(frame)

    play = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    play.alpha_composite(grad)
    play.putalpha(triangle_mask(size))
    canvas.alpha_composite(play)

    arrow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    arrow.alpha_composite(grad)
    arrow.putalpha(arrow_mask(size))
    canvas.alpha_composite(arrow)

    return canvas


outputs = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for filename, size in outputs:
    make_icon(size).save(ICONSET / filename)

print(ICONSET)
