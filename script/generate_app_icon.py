#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "Assets"
ICONSET_DIR = ASSET_DIR / "AppIcon.iconset"
PREVIEW_PATH = ASSET_DIR / "Bugu-AppIcon-1024.png"


SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def scale_points(points: list[tuple[float, float]], size: int) -> list[tuple[float, float]]:
    return [(x * size, y * size) for x, y in points]


def rounded_rectangle(draw: ImageDraw.ImageDraw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def draw_sound_arc(draw: ImageDraw.ImageDraw, center, radius, width, color, start=-42, end=42):
    box = [
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    ]
    draw.arc(box, start=start, end=end, fill=color, width=width)


def draw_icon(size: int) -> Image.Image:
    supersample = 4
    canvas_size = size * supersample
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    s = canvas_size

    graphite = (28, 33, 39, 255)
    graphite_2 = (42, 48, 57, 255)
    ivory = (250, 244, 226, 255)
    soft_gray = (181, 193, 203, 255)
    blue_gray = (132, 149, 164, 255)
    dark_feather = (55, 62, 72, 255)
    ink = (22, 26, 31, 255)
    teal = (83, 204, 186, 255)
    teal_dark = (35, 124, 116, 255)
    yellow = (247, 201, 72, 255)
    orange = (241, 128, 62, 255)
    coral = (246, 113, 91, 255)
    shadow = (9, 14, 20, 70)

    rounded_rectangle(draw, [0.055 * s, 0.055 * s, 0.945 * s, 0.945 * s], 0.215 * s, graphite)
    rounded_rectangle(draw, [0.095 * s, 0.095 * s, 0.905 * s, 0.905 * s], 0.18 * s, graphite_2)

    # Clock face base: the product is still a timed coding beacon.
    clock_box = [0.315 * s, 0.515 * s, 0.685 * s, 0.885 * s]
    draw.ellipse([clock_box[0] + 0.018 * s, clock_box[1] + 0.02 * s, clock_box[2] + 0.018 * s, clock_box[3] + 0.02 * s], fill=shadow)
    draw.ellipse(clock_box, fill=ivory, outline=teal_dark, width=max(2, int(0.018 * s)))
    center = (0.5 * s, 0.70 * s)
    draw.line([center, (0.5 * s, 0.585 * s)], fill=graphite, width=max(2, int(0.014 * s)))
    draw.line([center, (0.605 * s, 0.70 * s)], fill=graphite, width=max(2, int(0.014 * s)))
    draw.ellipse([center[0] - 0.017 * s, center[1] - 0.017 * s, center[0] + 0.017 * s, center[1] + 0.017 * s], fill=coral)

    # Real-cuckoo inspired side silhouette: gray body, long barred tail, yellow eye ring.
    tail = scale_points(
        [
            (0.57, 0.42),
            (0.86, 0.31),
            (0.77, 0.44),
            (0.88, 0.52),
            (0.57, 0.55),
        ],
        s,
    )
    draw.polygon([(x + 0.012 * s, y + 0.016 * s) for x, y in tail], fill=shadow)
    draw.polygon(tail, fill=dark_feather)

    tail_inner = scale_points([(0.62, 0.43), (0.81, 0.36), (0.75, 0.45), (0.82, 0.50), (0.61, 0.52)], s)
    draw.polygon(tail_inner, fill=blue_gray)
    for t in [0.66, 0.72, 0.78]:
        draw.line([(t * s, (0.405 + (t - 0.66) * 0.28) * s), ((t + 0.075) * s, (0.355 + (t - 0.66) * 0.36) * s)], fill=ivory, width=max(1, int(0.012 * s)))

    body = [0.245 * s, 0.345 * s, 0.66 * s, 0.64 * s]
    draw.ellipse([body[0] + 0.012 * s, body[1] + 0.018 * s, body[2] + 0.012 * s, body[3] + 0.018 * s], fill=shadow)
    draw.ellipse(body, fill=blue_gray)
    draw.ellipse([0.25 * s, 0.305 * s, 0.475 * s, 0.50 * s], fill=soft_gray)

    wing = scale_points(
        [
            (0.42, 0.43),
            (0.64, 0.46),
            (0.57, 0.59),
            (0.37, 0.57),
        ],
        s,
    )
    draw.polygon(wing, fill=(96, 110, 124, 255))
    for y in [0.47, 0.505, 0.54]:
        draw.arc([0.39 * s, (y - 0.055) * s, 0.64 * s, (y + 0.06) * s], start=7, end=168, fill=(196, 205, 213, 190), width=max(1, int(0.009 * s)))

    # Head, beak, and the distinctive yellow eye ring.
    head = [0.18 * s, 0.285 * s, 0.42 * s, 0.485 * s]
    draw.ellipse(head, fill=soft_gray)
    beak = scale_points([(0.185, 0.39), (0.08, 0.405), (0.19, 0.425)], s)
    draw.polygon(beak, fill=ink)
    beak_tip = scale_points([(0.088, 0.405), (0.055, 0.412), (0.09, 0.419)], s)
    draw.polygon(beak_tip, fill=yellow)
    eye_center = (0.325 * s, 0.372 * s)
    draw.ellipse([eye_center[0] - 0.034 * s, eye_center[1] - 0.034 * s, eye_center[0] + 0.034 * s, eye_center[1] + 0.034 * s], fill=yellow)
    draw.ellipse([eye_center[0] - 0.022 * s, eye_center[1] - 0.022 * s, eye_center[0] + 0.022 * s, eye_center[1] + 0.022 * s], fill=graphite_2)
    draw.ellipse([eye_center[0] - 0.010 * s, eye_center[1] - 0.010 * s, eye_center[0] + 0.010 * s, eye_center[1] + 0.010 * s], fill=ink)

    # Belly barring from the real bird, simplified so it survives small sizes.
    for x in [0.315, 0.35, 0.385, 0.42]:
        draw.line([(x * s, 0.54 * s), ((x + 0.055) * s, 0.625 * s)], fill=(36, 43, 52, 180), width=max(1, int(0.01 * s)))

    # Orange feet, perched on the clock rim.
    foot_width = max(2, int(0.014 * s))
    draw.line([(0.38 * s, 0.62 * s), (0.36 * s, 0.675 * s), (0.31 * s, 0.67 * s)], fill=orange, width=foot_width, joint="curve")
    draw.line([(0.47 * s, 0.62 * s), (0.455 * s, 0.675 * s), (0.515 * s, 0.668 * s)], fill=orange, width=foot_width, joint="curve")

    # Sound arcs: small, clean event cue.
    draw_sound_arc(draw, (0.755 * s, 0.315 * s), 0.065 * s, max(2, int(0.012 * s)), teal)
    draw_sound_arc(draw, (0.765 * s, 0.315 * s), 0.115 * s, max(2, int(0.012 * s)), (250, 244, 226, 220))

    # Tiny code prompt mark on the clock base.
    chevron = scale_points([(0.39, 0.81), (0.355, 0.785), (0.355, 0.835)], s)
    draw.line(chevron, fill=teal, width=max(2, int(0.016 * s)), joint="curve")
    draw.line([(0.425 * s, 0.835 * s), (0.50 * s, 0.835 * s)], fill=teal, width=max(2, int(0.016 * s)))

    if supersample > 1:
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    return image


def generate_from_source(source_path: Path) -> None:
    """Generate icon sizes from a user-provided source image."""
    source = Image.open(source_path).convert("RGBA")
    # Center-crop to a square if needed.
    width, height = source.size
    if width != height:
        min_dim = min(width, height)
        left = (width - min_dim) // 2
        top = (height - min_dim) // 2
        source = source.crop((left, top, left + min_dim, top + min_dim))

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    for filename, size in SIZES.items():
        icon = source.resize((size, size), Image.Resampling.LANCZOS)
        icon.save(ICONSET_DIR / filename)

    source.resize((1024, 1024), Image.Resampling.LANCZOS).save(PREVIEW_PATH)
    print(f"Wrote {ICONSET_DIR} from {source_path}")
    print(f"Wrote {PREVIEW_PATH}")


def main() -> None:
    source_path = ASSET_DIR / "logo-source.png"
    if source_path.exists():
        generate_from_source(source_path)
        return

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    for filename, size in SIZES.items():
        icon = draw_icon(size)
        icon.save(ICONSET_DIR / filename)

    draw_icon(1024).save(PREVIEW_PATH)
    print(f"Wrote {ICONSET_DIR}")
    print(f"Wrote {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
