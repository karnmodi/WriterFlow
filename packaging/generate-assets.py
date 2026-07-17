#!/usr/bin/env python3
"""Generate WriterFlow packaging icons and the DMG installer background.

Outputs (committed under packaging/ so release builds need no extra deps beyond
Pillow for regeneration):

  packaging/AppIcon.icns
  packaging/dmg/background.png
  packaging/dmg/background@2x.png

Brand colors match website/app/globals.css.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
ICONSET = ROOT / "AppIcon.iconset"
DMG_DIR = ROOT / "dmg"

INK = (17, 19, 26, 255)  # #11131a
PAPER = (244, 241, 233, 255)  # #f4f1e9
PAPER_DEEP = (235, 229, 216, 255)  # #ebe5d8
BLUE = (20, 40, 255, 255)  # #1428ff
BLUE_DEEP = (11, 31, 214, 255)  # #0b1fd6
COBALT = (158, 171, 255, 255)  # #9eabff

# Finder window content size in points (non-Retina). Background matches this;
# @2x is generated for sharp displays when Finder samples the larger file.
WINDOW_W = 720
WINDOW_H = 460

# Everything is rendered at a supersampled resolution and downscaled with
# Lanczos so curves, text, and diagonals come out smooth (Pillow's primitive
# drawing has no anti-aliasing of its own).
SUPERSAMPLE = 3


def rounded_rect_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def cubic_point(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    t: float,
) -> tuple[float, float]:
    u = 1.0 - t
    x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
    y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
    return (x, y)


def sample_cubic_pair(
    start: tuple[float, float],
    c1: tuple[float, float],
    c2: tuple[float, float],
    end: tuple[float, float],
    c3: tuple[float, float],
    c4: tuple[float, float],
    end2: tuple[float, float],
    steps: int,
) -> list[tuple[float, float]]:
    """Sample two sequential absolute cubic segments (matches website BrandMark paths)."""
    points: list[tuple[float, float]] = []
    for step in range(steps + 1):
        t = step / steps
        points.append(cubic_point(start, c1, c2, end, t))
    for step in range(1, steps + 1):
        t = step / steps
        points.append(cubic_point(end, c3, c4, end2, t))
    return points


def draw_brand_mark(size: int) -> Image.Image:
    """Dark rounded square with three cream wave strokes — matches website BrandMark.

    Rendered supersampled and downscaled so the rounded square and wave strokes
    are smoothly anti-aliased at every icon size.
    """
    ss = 4 if size <= 512 else 2
    render = size * ss

    img = Image.new("RGBA", (render, render), (0, 0, 0, 0))
    radius = render * (18 / 64)
    base = Image.new("RGBA", (render, render), INK)
    img.paste(base, (0, 0), rounded_rect_mask(render, radius))

    draw = ImageDraw.Draw(img)
    stroke = max(2, int(round(render * (4.4 / 64))))
    s = render / 64.0
    steps = max(64, render // 2)

    # Absolute cubics scaled from website/app/icon.svg viewBox paths.
    waves = [
        # M12 22.2 c7.4-2.8 13.9 3.1 21.1 1.1  6.3-1.7 11.3-4.7 18.9-1.4
        (
            (12.0, 22.2),
            (12.0 + 7.4, 22.2 - 2.8),
            (12.0 + 13.9, 22.2 + 3.1),
            (12.0 + 21.1, 22.2 + 1.1),
            (12.0 + 21.1 + 6.3, 22.2 + 1.1 - 1.7),
            (12.0 + 21.1 + 11.3, 22.2 + 1.1 - 4.7),
            (12.0 + 21.1 + 18.9, 22.2 + 1.1 - 1.4),
        ),
        # M12 32.3 c7.2-2.4 13.4 3.5 20.7 1.2  6.6-2.1 12-4.5 19.3-1.1
        (
            (12.0, 32.3),
            (12.0 + 7.2, 32.3 - 2.4),
            (12.0 + 13.4, 32.3 + 3.5),
            (12.0 + 20.7, 32.3 + 1.2),
            (12.0 + 20.7 + 6.6, 32.3 + 1.2 - 2.1),
            (12.0 + 20.7 + 12.0, 32.3 + 1.2 - 4.5),
            (12.0 + 20.7 + 19.3, 32.3 + 1.2 - 1.1),
        ),
        # M12 42.3 c7.7-2.2 13.1 3.2 20.7 1.2  6.9-1.8 12.3-4.3 19.3-.9
        (
            (12.0, 42.3),
            (12.0 + 7.7, 42.3 - 2.2),
            (12.0 + 13.1, 42.3 + 3.2),
            (12.0 + 20.7, 42.3 + 1.2),
            (12.0 + 20.7 + 6.9, 42.3 + 1.2 - 1.8),
            (12.0 + 20.7 + 12.3, 42.3 + 1.2 - 4.3),
            (12.0 + 20.7 + 19.3, 42.3 + 1.2 - 0.9),
        ),
    ]

    for start, c1, c2, mid, c3, c4, end in waves:
        pts = sample_cubic_pair(start, c1, c2, mid, c3, c4, end, steps)
        scaled = [(x * s, y * s) for x, y in pts]
        draw.line(scaled, fill=PAPER, width=stroke, joint="curve")
        r = stroke / 2
        for x, py in (scaled[0], scaled[-1]):
            draw.ellipse((x - r, py - r, x + r, py + r), fill=PAPER)

    return img.resize((size, size), Image.LANCZOS)


def write_iconset() -> Path:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    # iconutil expected names → pixel size
    entries = {
        "icon_16x16.png": 16,
        "diana.k@example.org": 32,
        "icon_32x32.png": 32,
        "ivan.p@example.net": 64,
        "icon_128x128.png": 128,
        "wendy.h@example.net": 256,
        "icon_256x256.png": 256,
        "wendy.h@example.net": 512,
        "icon_512x512.png": 512,
        "walt.e@example.net": 1024,
    }
    for name, px in entries.items():
        draw_brand_mark(px).save(ICONSET / name, "PNG")
    return ICONSET


def build_icns() -> Path:
    write_iconset()
    icns = ROOT / "AppIcon.icns"
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(icns)], check=True)
    return icns


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Helvetica.ttc",
            ]
        )
    else:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/System/Library/Fonts/Helvetica.ttc",
            ]
        )
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def arrow_points(s: float) -> list[tuple[float, float]]:
    """Bold right-pointing arrow silhouette between the two cards (1x coords × s)."""
    x0, tip, y = 298.0, 424.0, 226.0
    shaft_hw, head_hw, head_len = 13.0, 28.0, 42.0
    base = tip - head_len
    pts = [
        (x0, y - shaft_hw),
        (base, y - shaft_hw),
        (base, y - head_hw),
        (tip, y),
        (base, y + head_hw),
        (base, y + shaft_hw),
        (x0, y + shaft_hw),
    ]
    return [(px * s, py * s) for px, py in pts]


def arrow_mask(size: tuple[int, int], pts: list[tuple[float, float]]) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask


def vertical_gradient(
    size: tuple[int, int],
    bbox: tuple[float, float, float, float],
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
) -> Image.Image:
    """RGBA image with a vertical gradient spanning bbox rows (constant per row)."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    y0, y1 = int(bbox[1]), int(bbox[3])
    span = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        t = (y - y0) / span
        draw.line([(int(bbox[0]), y), (int(bbox[2]), y)], fill=(*lerp(top, bottom, t), 255))
    return img


def draw_3d_arrow(img: Image.Image, s: float) -> Image.Image:
    """Extruded, shaded 'drag this way' arrow with drop shadow and gloss."""
    size = img.size
    pts = arrow_points(s)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    bbox = (min(xs), min(ys), max(xs), max(ys))

    # 1. Soft drop shadow under the whole arrow.
    shadow_pts = [(x, y + 12 * s) for x, y in pts]
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(shadow_pts, fill=(17, 19, 26, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=7 * s))
    img = Image.alpha_composite(img, shadow)

    # 2. Extruded side face — the same silhouette shifted down, in dark graphite.
    depth = 7 * s
    side_color = (28, 31, 40, 255)
    extrude = Image.new("RGBA", size, (0, 0, 0, 0))
    edraw = ImageDraw.Draw(extrude)
    extrude_pts = [(x, y + depth) for x, y in pts]
    edraw.polygon(extrude_pts, fill=side_color)
    # Fill the gap between top and bottom faces so the extrusion reads as a solid.
    for a, b in zip(pts, pts[1:] + pts[:1]):
        edraw.polygon([a, b, (b[0], b[1] + depth), (a[0], a[1] + depth)], fill=side_color)
    img = Image.alpha_composite(img, extrude)

    # 3. Top face with a vertical light-to-dark graphite gradient (ink brand tone).
    grad = vertical_gradient(
        size,
        bbox,
        top=(148, 153, 166),
        bottom=(58, 62, 76),
    )
    face = Image.new("RGBA", size, (0, 0, 0, 0))
    face.paste(grad, (0, 0), arrow_mask(size, pts))
    img = Image.alpha_composite(img, face)

    # 4. Glossy highlight across the upper third of the top face.
    gloss_h = (bbox[3] - bbox[1]) * 0.42
    gloss_grad = vertical_gradient(
        size,
        (bbox[0], bbox[1], bbox[2], bbox[1] + gloss_h),
        top=(255, 255, 255),
        bottom=(255, 255, 255),
    )
    # Fade the gloss out toward its lower edge.
    fade = Image.new("L", size, 0)
    fdraw = ImageDraw.Draw(fade)
    for y in range(int(bbox[1]), int(bbox[1] + gloss_h) + 1):
        t = (y - bbox[1]) / max(1.0, gloss_h)
        fdraw.line([(int(bbox[0]), y), (int(bbox[2]), y)], fill=int(90 * (1.0 - t)))
    gloss_mask = Image.composite(fade, Image.new("L", size, 0), arrow_mask(size, pts))
    gloss = Image.new("RGBA", size, (0, 0, 0, 0))
    gloss.paste(gloss_grad, (0, 0), gloss_mask)
    img = Image.alpha_composite(img, gloss)

    return img


def render_background(s: int) -> Image.Image:
    """Render the installer background at pixel multiplier s (1x coords × s)."""
    w, h = WINDOW_W * s, WINDOW_H * s
    img = Image.new("RGBA", (w, h), PAPER)
    draw = ImageDraw.Draw(img)

    # Soft vertical wash into deeper paper.
    for y in range(h):
        t = y / max(1, h - 1)
        color = lerp(PAPER, PAPER_DEEP, t * 0.55)
        draw.line([(0, y), (w, y)], fill=color)

    # Soft neutral glow behind the install path.
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    cx, cy = w // 2, int(h * 0.48)
    gdraw.ellipse(
        (cx - 180 * s, cy - 90 * s, cx + 180 * s, cy + 90 * s),
        fill=(255, 255, 255, 70),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=36 * s))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # Top wordmark.
    mark = draw_brand_mark(34 * s)
    title_font = load_font(22 * s, bold=True)
    subtitle_font = load_font(13 * s)
    hint_font = load_font(12 * s)

    title = "WriterFlow"
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_w = title_bbox[2] - title_bbox[0]
    gap = 10 * s
    total_w = mark.width + gap + title_w
    start_x = (w - total_w) // 2
    mark_y = 26 * s
    img.alpha_composite(mark, (start_x, mark_y))
    draw.text(
        (start_x + mark.width + gap, mark_y + (mark.height - (title_bbox[3] - title_bbox[1])) // 2 - 1 * s),
        title,
        font=title_font,
        fill=INK,
    )

    tagline = "Always-on writing assistant for Mac"
    tag_bbox = draw.textbbox((0, 0), tagline, font=subtitle_font)
    tag_w = tag_bbox[2] - tag_bbox[0]
    draw.text(((w - tag_w) // 2, 70 * s), tagline, font=subtitle_font, fill=(17, 19, 26, 140))

    # Landing cards behind each Finder icon. Sized to contain the 128px icon AND
    # its filename label (Finder draws labels at roughly y 296–316 for icons
    # centered at y 230), so labels sit inside the card with clear margins.
    card_w, card_h = 204, 186
    card_top = 148
    for ccx in (180, 540):
        x0 = (ccx - card_w // 2) * s
        y0 = card_top * s
        x1 = (ccx + card_w // 2) * s
        y1 = (card_top + card_h) * s

        shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow)
        sdraw.rounded_rectangle(
            (x0, y0 + 6 * s, x1, y1 + 6 * s),
            radius=26 * s,
            fill=(17, 19, 26, 30),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=10 * s))
        img = Image.alpha_composite(img, shadow)
        draw = ImageDraw.Draw(img)
        draw.rounded_rectangle(
            (x0, y0, x1, y1),
            radius=26 * s,
            fill=(255, 255, 255, 178),
            outline=(17, 19, 26, 26),
            width=max(1, s),
        )

    # 3D drag arrow between the cards.
    img = draw_3d_arrow(img, s)
    draw = ImageDraw.Draw(img)

    # Bottom instruction — clear of the cards and Finder labels.
    hint = "Drag WriterFlow into Applications to install"
    hint_bbox = draw.textbbox((0, 0), hint, font=hint_font)
    hint_w = hint_bbox[2] - hint_bbox[0]
    hint_y = 392 * s
    pad_x, pad_y = 16 * s, 8 * s
    pill = [
        (w - hint_w) // 2 - pad_x,
        hint_y - pad_y,
        (w + hint_w) // 2 + pad_x,
        hint_y + (hint_bbox[3] - hint_bbox[1]) + pad_y,
    ]
    draw.rounded_rectangle(pill, radius=15 * s, fill=(255, 255, 255, 195), outline=(17, 19, 26, 24))
    draw.text(((w - hint_w) // 2, hint_y), hint, font=hint_font, fill=(17, 19, 26, 205))

    # Thin top accent rule in brand blue.
    draw.rectangle((0, 0, w, 3 * s), fill=BLUE_DEEP)

    return img


def draw_background(scale: int = 1) -> Image.Image:
    """Supersampled render downscaled to the target scale for smooth edges."""
    raw = render_background(scale * SUPERSAMPLE)
    return raw.resize((WINDOW_W * scale, WINDOW_H * scale), Image.LANCZOS).convert("RGB")


def write_backgrounds() -> None:
    DMG_DIR.mkdir(parents=True, exist_ok=True)
    draw_background(1).save(DMG_DIR / "background.png", "PNG", optimize=True)
    draw_background(2).save(DMG_DIR / "background@2x.png", "PNG", optimize=True)


def main() -> int:
    print("▸ Generating AppIcon.icns")
    icns = build_icns()
    print(f"  wrote {icns.relative_to(ROOT.parent)}")

    print("▸ Generating DMG backgrounds")
    write_backgrounds()
    print(f"  wrote packaging/dmg/background.png ({WINDOW_W}×{WINDOW_H})")
    print(f"  wrote packaging/dmg/background@2x.png ({WINDOW_W * 2}×{WINDOW_H * 2})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
