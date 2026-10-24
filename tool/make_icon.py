#!/usr/bin/env python3
"""Writes a plain SARCADE icon (navy square, white « S » made of blocks) as
PNG with the standard library only, for packages that need an icon file."""
import struct
import sys
import zlib

NAVY = (0x17, 0x3A, 0x6A)
WHITE = (0xFF, 0xFF, 0xFF)
# 5x7 « S »
GLYPH = ["01110", "10001", "10000", "01110", "00001", "10001", "01110"]


def pixel(x: int, y: int, size: int):
    cell = size // 9
    gx, gy = (x - 2 * cell) // cell, (y - cell) // cell
    if 0 <= gx < 5 and 0 <= gy < 7 and GLYPH[gy][gx] == "1":
        return WHITE
    return NAVY


def main(path: str, size: int) -> None:
    rows = b"".join(b"\x00" + b"".join(bytes(pixel(x, y, size)) for x in range(size)) for y in range(size))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 256)
