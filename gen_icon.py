#!/usr/bin/env python3
"""Generate MaruEdit.icns from the checked-in production icon master."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

from PIL import Image


ROOT = Path(__file__).resolve().parent
MASTER_PATH = ROOT / "MaruEditIconMaster.png"
OUTPUT_PATH = ROOT / "MaruEdit.icns"
SIZE = 1024


def load_master():
    """Load and validate the transparent 1024px production artwork."""
    image = Image.open(MASTER_PATH).convert("RGBA")
    if image.size != (SIZE, SIZE):
        raise ValueError(f"icon master must be {SIZE}x{SIZE}, got {image.size}")
    alpha = image.getchannel("A")
    if alpha.getextrema() != (0, 255):
        raise ValueError("icon master must contain transparent corners and opaque artwork")
    return image


def render_size(master, size):
    """Downsample the high-contrast architectural mark for one icon slot."""
    return master.resize((size, size), Image.Resampling.LANCZOS)


def create_icns(image, output_path):
    """Create every standard macOS icon slot from the master image."""
    tmpdir = tempfile.mkdtemp(prefix="maruedit-icon-")
    try:
        iconset = os.path.join(tmpdir, "MaruEdit.iconset")
        os.makedirs(iconset)
        for size in [16, 32, 64, 128, 256, 512, 1024]:
            render_size(image, size).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
            if size <= 512:
                render_size(image, size * 2).save(
                    os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
        subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", str(output_path)], check=True)
    finally:
        shutil.rmtree(tmpdir)
    print(f"Created {output_path}")


if __name__ == "__main__":
    create_icns(load_master(), OUTPUT_PATH)
