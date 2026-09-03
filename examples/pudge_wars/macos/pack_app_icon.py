#!/usr/bin/env python3
"""Turn a Flux app-icon PNG into a full-bleed square, plus .ico."""

from __future__ import annotations

import argparse
import struct
import sys
from collections import deque
from pathlib import Path

from PIL import Image


def is_margin(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return red > 230 and green > 230 and blue > 230 and abs(red - green) < 20


def margin_mask(image: Image.Image) -> list[list[bool]]:
    width, height = image.size
    pixels = image.load()
    seen = [[False] * width for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()

    def enqueue(x: int, y: int) -> None:
        if x < 0 or y < 0 or x >= width or y >= height:
            return
        if seen[y][x] or not is_margin(pixels[x, y]):
            return
        seen[y][x] = True
        queue.append((x, y))

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)
    while queue:
        x, y = queue.popleft()
        enqueue(x - 1, y)
        enqueue(x + 1, y)
        enqueue(x, y - 1)
        enqueue(x, y + 1)
    return seen


def content_bounds(mask: list[list[bool]]) -> tuple[int, int, int, int]:
    height = len(mask)
    width = len(mask[0])
    x0, y0, x1, y1 = width, height, 0, 0
    for y in range(height):
        for x in range(width):
            if mask[y][x]:
                continue
            x0 = min(x0, x)
            y0 = min(y0, y)
            x1 = max(x1, x)
            y1 = max(y1, y)
    if x1 <= x0:
        return (0, 0, width, height)
    pad_x = max(12, (x1 - x0) // 28)
    pad_y = max(12, (y1 - y0) // 28)
    return (
        x0 + pad_x,
        y0 + pad_y,
        x1 + 1 - pad_x,
        y1 + 1 - pad_y,
    )


def sample_field_color(image: Image.Image, mask: list[list[bool]]) -> tuple[int, int, int]:
    width, height = image.size
    pixels = image.load()
    samples: list[tuple[int, int, int]] = []
    for y in range(height):
        for x in range(width):
            if mask[y][x]:
                continue
            red, green, blue = pixels[x, y]
            if green < 50 or green < red + 8:
                continue
            lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            if lum < 25 or lum > 90:
                continue
            near_margin = False
            for nx, ny in ((x - 2, y), (x + 2, y), (x, y - 2), (x, y + 2)):
                if 0 <= nx < width and 0 <= ny < height and mask[ny][nx]:
                    near_margin = True
                    break
            if near_margin:
                continue
            samples.append((red, green, blue))
    if not samples:
        return (24, 72, 28)
    samples.sort()
    return samples[len(samples) // 2]


def flood_fill_margin(image: Image.Image) -> Image.Image:
    rgb = image.convert('RGB')
    mask = margin_mask(rgb)
    x0, y0, x1, y1 = content_bounds(mask)
    cropped = rgb.crop((x0, y0, x1, y1))
    fill = sample_field_color(rgb, mask)
    inner_mask = margin_mask(cropped)
    pixels = cropped.load()
    for y in range(cropped.height):
        for x in range(cropped.width):
            if inner_mask[y][x]:
                pixels[x, y] = fill
    edge = 6
    for y in range(cropped.height):
        for x in range(cropped.width):
            if x >= edge and y >= edge and x < cropped.width - edge and y < cropped.height - edge:
                continue
            red, green, blue = pixels[x, y]
            lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            if lum > 110:
                pixels[x, y] = fill
    return cropped.resize((1024, 1024), Image.Resampling.LANCZOS)


def write_ico(path: Path, images: list[Image.Image]) -> None:
    blobs: list[bytes] = []
    entries = b''
    offset = 6 + 16 * len(images)
    for image in images:
        size = max(image.size)
        buf = __import__('io').BytesIO()
        image.save(buf, format='PNG')
        data = buf.getvalue()
        width = 0 if size >= 256 else size
        entries += struct.pack(
            '<BBBBHHII',
            width,
            width,
            0,
            0,
            1,
            32,
            len(data),
            offset,
        )
        blobs.append(data)
        offset += len(data)
    header = struct.pack('<HHH', 0, 1, len(images))
    path.write_bytes(header + entries + b''.join(blobs))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--png', type=Path, required=True)
    parser.add_argument('--ico', type=Path)
    args = parser.parse_args()
    filled = flood_fill_margin(Image.open(args.source))
    args.png.parent.mkdir(parents=True, exist_ok=True)
    filled.save(args.png, format='PNG')
    if args.ico:
        sizes = (16, 32, 48, 256)
        icons = [
            filled.resize((size, size), Image.Resampling.LANCZOS)
            for size in sizes
        ]
        write_ico(args.ico, icons)
    print(f'wrote {args.png}')
    if args.ico:
        print(f'wrote {args.ico}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
