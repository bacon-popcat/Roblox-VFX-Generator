"""Impact textures for the redesigned effects: ImpactStar, Splinters, ClawSlash (flipbooks),
Glint and ShockRing (light). White with the shape in alpha; the particle's Color tints them.

Run: python assets/textures/impact.py   (or from Blender's Python; needs numpy)
Writes the PNGs (+ .flipbook.json notes and previews) next to this file. Check the sheets with
node tools/vfx/flipbook.mjs assets/textures/*.flipbook.png
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "vfx"))
import numpy  # noqa: E402
import vfxtex  # noqa: E402
import examples  # noqa: E402

vfxtex.OUTPUT_DIR = HERE


def glint(size):
    """Four equal straight arms fading toward their tips from one smooth hot core, faint halo."""
    x, y = vfxtex.tex_coords(size)
    r = numpy.hypot(x, y)

    def arm(along, across, length, width):
        fade = numpy.clip(1 - numpy.abs(along) / length, 0, 1)
        return numpy.exp(-(across / (width * fade + 1e-4)) ** 2) * fade ** 1.5

    rays = numpy.maximum(arm(y, x, 0.95, 0.035), arm(x, y, 0.95, 0.035))
    core = numpy.exp(-(r / 0.07) ** 2)
    halo = 0.3 * numpy.exp(-(r / 0.3) ** 2)
    return numpy.clip(rays + core + halo, 0, 1)


def shock_ring(size):
    """A soft shock ring that varies round the circle: a bright thick arc thinning and fading
    round the rest, with a second weaker swell so it never reads as one even band."""
    x, y = vfxtex.tex_coords(size)
    r, a = vfxtex.tex_polar(x, y)
    w = 0.5 + 0.5 * numpy.cos(a - 0.6)
    w2 = 0.5 + 0.5 * numpy.cos(2 * a + 1.9)
    w = 0.75 * w + 0.25 * w2
    ring = numpy.exp(-((r - 0.78) / (0.012 + 0.05 * w)) ** 2) * (0.3 + 0.7 * w)
    return numpy.clip(ring, 0, 1)


def draw():
    examples.draw("ImpactStar")
    examples.draw("Splinters")
    examples.draw("ClawSlash")
    vfxtex.draw_texture("Glint", glint, size=512)
    vfxtex.draw_texture("ShockRing", shock_ring, size=1024)


if __name__ == "__main__":
    draw()
