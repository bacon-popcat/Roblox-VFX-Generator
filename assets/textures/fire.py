"""Fire and smoke sheets for the redesigned explosions: FireBurstA and FireBurstB (two seeds
of a white-hot puff that grows by a third of the way, chars inside and breaks up, edges
glowing in places), BurnOut (charcoal with cooling cracks that swells and tears) and
DustPuff (mottled heavy dust/smoke with a broken rim that keeps changing shape).

Value is baked as grey (alpha, value): under the fire body's Color the white heart reads hot
and the charred inside dark. Run: python assets/textures/fire.py (needs numpy).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "vfx"))
import numpy  # noqa: E402
import vfxtex  # noqa: E402
import examples  # noqa: E402

vfxtex.OUTPUT_DIR = HERE


def make_fire_burst(seed):
    """A fire burst like examples.fire_burst, with its own tongues and noise per seed."""
    rng = numpy.random.default_rng(seed)
    tongues = [(rng.uniform(-0.6, 0.6) + (numpy.pi / 2 if i % 3 else rng.uniform(0, 2 * numpy.pi)),
                rng.uniform(0.15, 0.4), rng.uniform(0.07, 0.13), rng.choice([-1, 1])) for i in range(11)]
    churn = vfxtex.tex_noise(256, scale=5, octaves=4, seed=seed + 8)
    rag = vfxtex.tex_noise(256, scale=12, octaves=3, seed=seed + 4)

    def frame(t, size):
        x, y = vfxtex.tex_coords(size)
        wx, wy = vfxtex.tex_warp(x, y, amount=0.1, scale=4, seed=seed + 2, t=t * 1.6)
        grow = vfxtex.tex_ease(t * 3)
        radius = 0.16 + 0.22 * grow
        body = vfxtex.tex_blob(wx, wy, radius=radius, lumps=9, roughness=0.75, seed=seed + 5)
        for n, (angle, reach, width, curl) in enumerate(tongues):
            base = (numpy.cos(angle) * radius * 0.7, numpy.sin(angle) * radius * 0.7)
            lick = reach * grow * (0.7 + 0.3 * numpy.sin(t * 19 + n * 2.3))
            tip = (base[0] + numpy.cos(angle) * lick, base[1] + numpy.sin(angle) * lick + 0.05 * t)
            bend = ((base[0] + tip[0]) / 2 - numpy.sin(angle) * 0.06 * curl, (base[1] + tip[1]) / 2 + numpy.cos(angle) * 0.06 * curl)
            path = vfxtex.tex_curve([base, bend, tip], 16)
            body = numpy.maximum(body, vfxtex.tex_stroke(wx, wy, path, [width * (1 - 0.5 * t), 0.0]))
        body = body + (vfxtex.tex_sample(rag, wx * 0.5 + t * 0.2, wy * 0.5 - t * 0.5) - 0.5) * 0.08
        burn = vfxtex.tex_sample(churn, x * 0.6 + 0.3, y * 0.6 - t * 0.4) - max(0.0, t - 0.2) * 1.4 + 0.1 + body * 0.6
        cool = min(max((t - 0.2) / 0.4, 0.0), 1.0)
        alpha = vfxtex.tex_edge(body, soft=0.008 + 0.03 * cool) * vfxtex.tex_edge(burn, soft=0.02 + 0.06 * cool)
        mottle = vfxtex.tex_sample(rag, wx * 0.4 - t * 0.2, wy * 0.4 + t * 0.3) - 0.5
        rim = (1 - vfxtex.tex_edge(numpy.minimum(body, burn / 3), 0.035 + mottle * 0.06, soft=0.015)) * vfxtex.tex_edge(mottle, -0.1, soft=0.1)
        heat = vfxtex.tex_sample(churn, wx * 0.5 - t * 0.3, wy * 0.5 + t * 0.6) + body * 2.5 - 0.05 - t * 1.5
        core = (0.55 + mottle * 0.3) * (1 - 0.9 * cool)
        value = core + (0.7 - 0.35 * cool - core) * rim * cool
        return alpha * (1 - 0.3 * cool * (1 - rim)), numpy.maximum(value, vfxtex.tex_edge(heat, 0.5, soft=0.06))

    return frame


BILLOWS = vfxtex.tex_noise(256, scale=5, octaves=5, seed=7)
GRIT = vfxtex.tex_noise(256, scale=16, octaves=3, seed=9)
HOLES = vfxtex.tex_noise(256, scale=6, seed=1)


def dust(t, size):
    """Heavy mottled dust: a rim broken by billows that roll fast, light and dark inside,
    torn by holes that open from ~25% so the outline keeps changing every frame."""
    x, y = vfxtex.tex_coords(size)
    wx, wy = vfxtex.tex_warp(x, y, amount=0.16, scale=5, seed=3, t=t * 1.8)
    radius = 0.2 + 0.26 * vfxtex.tex_ease(t * 2) + 0.08 * t
    body = vfxtex.tex_blob(wx, wy, radius=radius, lumps=11, roughness=0.85, seed=6)
    churn = vfxtex.tex_sample(BILLOWS, x * 0.7 + t * 0.6, y * 0.7 - t * 0.9)
    edge = body + (vfxtex.tex_sample(GRIT, x + t * 0.7, y - t * 0.4) - 0.5) * 0.4
    holes = vfxtex.tex_sample(HOLES, x * 0.5 + 0.2 + t * 0.3, y * 0.5 + t * 0.5) - max(0.0, t - 0.2) * 1.8 + 0.5
    alpha = vfxtex.tex_edge(edge, soft=0.01) * vfxtex.tex_edge(holes + body * 0.3, soft=0.05)
    shade = 0.5 + (churn - 0.5) * 1.9 + 0.15 * numpy.clip(y / radius, -1, 1)
    return alpha, numpy.clip(shade, 0.12, 0.95)


def draw():
    vfxtex.draw_flipbook("FireBurstA", make_fire_burst(3), grid=4, fps=30)
    vfxtex.draw_flipbook("FireBurstB", make_fire_burst(17), grid=4, fps=30)
    examples.draw("BurnOut")
    vfxtex.draw_flipbook("DustPuff", dust, grid=4, fps=16)


if __name__ == "__main__":
    draw()
