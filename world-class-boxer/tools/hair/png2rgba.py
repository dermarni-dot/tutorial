"""Converts an image (PNG, ...) to raw RGBA8, rows top to bottom, straight alpha: what the lune simulator
(tools/sim) reads in place of an EditableImage's ReadPixelsBuffer (lune cannot decode PNG).

    /opt/bpyenv/bin/python png2rgba.py IN.png OUT.rgba [IN2.png OUT2.rgba ...]

Prints one line per pair: "<width> <height> <OUT>". Greyscale / palette / LA images are expanded to RGBA.
"""
import sys

from PIL import Image


def convert(src, dst):
    with Image.open(src) as im:
        rgba = im.convert("RGBA")
        with open(dst, "wb") as f:
            f.write(rgba.tobytes())
        return rgba.size


def main(argv):
    if len(argv) < 2 or len(argv) % 2:
        print(__doc__, file=sys.stderr)
        return 2
    for i in range(0, len(argv), 2):
        w, h = convert(argv[i], argv[i + 1])
        print(w, h, argv[i + 1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
