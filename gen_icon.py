#!/usr/bin/env python3
"""Generate MaruEdit's placeholder app icon.

This is an original design: a flat rounded square with a single hand-drawn-
style ring ("maru", 丸 — Japanese for "circle"). It intentionally does not
reuse LiteEdit's code-editor-window artwork (title bar, tabs, syntax-colored
code lines) per ROADMAP.md task M0-03, which requires an original placeholder
icon until MaruEdit's real branding is finalized.
"""
from PIL import Image, ImageDraw
import subprocess, os, tempfile

SIZE = 1024
R = 180  # corner radius, matches the standard macOS icon grid

BACKGROUND = (30, 27, 46)      # deep indigo
RING = (255, 138, 61)          # warm orange accent


def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    d.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=R, fill=BACKGROUND)

    # A single clean ring ("maru", 丸 — Japanese for "circle").
    cx, cy = SIZE // 2, SIZE // 2
    outer, inner = 320, 210
    d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=RING)
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=BACKGROUND)

    mask = rounded_rect_mask(SIZE, R)
    img.putalpha(mask)
    return img


def create_icns(img, output_path):
    """Create .icns from a PIL image using iconutil."""
    tmpdir = tempfile.mkdtemp()
    iconset = os.path.join(tmpdir, "MaruEdit.iconset")
    os.makedirs(iconset)

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        resized = img.resize((s, s), Image.LANCZOS)
        resized.save(os.path.join(iconset, f"icon_{s}x{s}.png"))
        if s <= 512:
            double = img.resize((s * 2, s * 2), Image.LANCZOS)
            double.save(os.path.join(iconset, f"icon_{s}x{s}@2x.png"))

    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", output_path], check=True)
    subprocess.run(["rm", "-rf", tmpdir])
    print(f"Created {output_path}")


if __name__ == "__main__":
    icon = draw_icon()
    icon.save("/tmp/maruedit_icon_preview.png")

    icns_path = os.path.join(os.path.dirname(__file__), "MaruEdit.icns")
    create_icns(icon, icns_path)
