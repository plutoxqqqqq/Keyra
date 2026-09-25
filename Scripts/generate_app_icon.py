#!/usr/bin/env python3
"""Generate Keyra's app icon.

Pure standard library: the PNG is written by hand (zlib + struct) so the icon
can be regenerated on Windows, macOS or Linux with no image libraries, and the
repository never needs a binary blob that nobody can reproduce.

Usage:
    python Scripts/generate_app_icon.py
Writes:
    CustomKeyboardApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""

from __future__ import annotations

import os
import struct
import sys
import zlib

SIZE = 1024
OUTPUT = os.path.join(
    "CustomKeyboardApp",
    "Assets.xcassets",
    "AppIcon.appiconset",
    "AppIcon-1024.png",
)

# Palette (0-255 RGB)
TOP = (124, 84, 246)       # violet
BOTTOM = (28, 18, 58)      # deep indigo
KEY = (245, 244, 255)      # key face
KEY_EDGE = (206, 200, 240)  # key border
ACCENT = (255, 214, 102)   # highlighted key
SHADOW = (14, 8, 30)       # key drop shadow


def mix(a, b, t):
    """Linear interpolation between two RGB tuples."""
    t = max(0.0, min(1.0, t))
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def rounded_rect_alpha(x, y, left, top, right, bottom, radius):
    """Coverage of a rounded rectangle at pixel centre (x, y)."""
    cx = x + 0.5
    cy = y + 0.5
    if cx < left or cx > right or cy < top or cy > bottom:
        return 0.0
    r = min(radius, (right - left) / 2.0, (bottom - top) / 2.0)
    # Distance to the nearest inner corner centre.
    dx = max(left + r - cx, 0.0, cx - (right - r))
    dy = max(top + r - cy, 0.0, cy - (bottom - r))
    distance = (dx * dx + dy * dy) ** 0.5
    # 1px analytic anti-aliasing.
    return max(0.0, min(1.0, r - distance + 0.5))


def build_rows():
    rows = []
    # Keyboard grid geometry.
    columns, row_count = 4, 3
    key_w, key_h = 168.0, 138.0
    gap = 26.0
    grid_w = columns * key_w + (columns - 1) * gap
    grid_h = row_count * key_h + (row_count - 1) * gap
    grid_left = (SIZE - grid_w) / 2.0
    grid_top = (SIZE - grid_h) / 2.0 + 26.0
    radius = 34.0

    for y in range(SIZE):
        row = bytearray()
        # Vertical gradient with a soft diagonal sheen.
        for x in range(SIZE):
            t = (y / (SIZE - 1)) * 0.85 + (x / (SIZE - 1)) * 0.15
            color = mix(TOP, BOTTOM, t)

            # Keys.
            for r in range(row_count):
                key_top = grid_top + r * (key_h + gap)
                for c in range(columns):
                    key_left = grid_left + c * (key_w + gap)
                    # Shadow first.
                    s = rounded_rect_alpha(
                        x, y, key_left + 2, key_top + 10, key_left + key_w + 2, key_top + key_h + 10, radius
                    )
                    if s > 0:
                        color = mix(color, SHADOW, 0.45 * s)
                    a = rounded_rect_alpha(x, y, key_left, key_top, key_left + key_w, key_top + key_h, radius)
                    if a > 0:
                        is_accent = (r == 0 and c == 0)
                        face = ACCENT if is_accent else KEY
                        color = mix(color, face, 0.94 * a)
                        edge = rounded_rect_alpha(
                            x, y, key_left, key_top, key_left + key_w, key_top + key_h, radius
                        ) - rounded_rect_alpha(
                            x, y, key_left + 3, key_top + 3, key_left + key_w - 3, key_top + key_h - 3, radius - 3
                        )
                        if edge > 0:
                            color = mix(color, KEY_EDGE, 0.65 * min(1.0, edge))
            row.extend(color)
        rows.append(bytes(row))
    return rows


def write_png(path, rows, width, height):
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type 0
        raw.extend(row)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit truecolour, no alpha
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)
    return len(png)


def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(project_root)
    rows = build_rows()
    written = write_png(OUTPUT, rows, SIZE, SIZE)
    print(f"Wrote {OUTPUT} ({SIZE}x{SIZE}, {written} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
