# Recipes

Timings are in effect seconds. Layers are listed in draw-priority order.
"Mesh:" notes name the MeshFactory generator to use (see `meshes.md`).
The studied numbers behind these (palette, value, brightness, timing) are in `design.md`;
fire and smoke in `explosions.md`; projectiles, slashes, beams and auras in `motion.md`.

**Recreating a reference: Oscar's corrections so far** (they came from playtest
screenshots, not from the reference video). Apply them where Roqer's guidance says nothing;
where they conflict, follow `design.md` / `explosions.md` / `motion.md` (`SKILL.md`,
Precedence). The main conflict: a fire body is a boiling mass of flipbook particles
(`explosions.md`), not beam sheets carrying one image.
- Big flame sheets (walls, curtains, central columns) stay fixed in the world, lying
  along the effect's shape, not turned to the camera. Use beams with `FaceCamera = false`
  (orientation rule in `structure.md` "Engine gotchas"). Particles can only face the
  camera, so they can't be fixed this way; say so instead of trying.
- Fire walls must be dense with no see-through gaps, including at the sides. Leave no
  gaps between particles, back the particles with an opaque layer, and don't thin the
  edges (details in the lava fissure recipe).
- Flames should rush upward, not drift. Speed them up and cut their lifetime by the same
  factor so the height stays put (height ≈ Speed × Lifetime, a bit less with Drag).
- Fire walls sway side to side while they burn.
- Wind and swirl arcs should rise as they spin out, not sit flat on the ground, and stay
  subtle (start ~0.4 transparent).

## Impact skeleton (studied)
From Roqer's measurements of published effects (https://github.com/S4US/Roqer, `vfx-craft.md`,
AGPL-3.0-or-later). A floor, not a target: fill each role with your own texture and colour,
add or drop roles as the idea needs. R = the effect's radius in studs; times from the hit.
Each layer is usually its own single-sprite burst (`ctx.Emit(emitter, 1-6)`), timed with
`ctx.Wait`.

| Time | Role | Make |
| --- | --- | --- |
| -0.15 s | Anticipation | A glow that shrinks from 1.5R to 0 over 0.1-0.15 s, spinning fast (`RotSpeed` -700 to -500) |
| 0 | Flash | A soft ball or four-point flare growing 0 to 2.5R, Lifetime 0.06-0.1, Brightness 10, `ZOffset` in front |
| +0.03 s | Impact stars | A 4x4 sheet that bursts open (`drawing-textures.md`), Lifetime 0.075-0.15, 2-6 particles, as the three-value stack: colour (`ZOffset` z, `LightEmission` -1, Brightness 5), its black twin (same size, life and count, z to z + 0.25) and a small white copy (z + 1, Brightness ~60) |
| +0.03 s | Black backing | A soft black blob behind (`ZOffset` -1), 2-4R, Transparency 0.35 → 1 |
| +0.05 s | Streaks | `VelocityParallel` with `Squash` 3 → 1, Speed 60-200, Drag 8-12, size with an envelope, a few black twins |
| +0.05 s | Ring | A flat `VelocityPerpendicular` ring (Speed ~0.01, `EmissionDirection` Top, attachment level with the ground) growing to 2-3R over 0.2-0.4 s, Transparency 0 → 1.3 |
| +0.03 s | Fire body | For fire: 2-4 fire-burst flipbook layers, never one image scaling (`explosions.md`) |
| +0.05 s | Smoke | The same burst living 1.5-3 times as long: self-lit mid-grey sheets (or tinted by the fire), half transparent at their most solid, slowed, gone by about 1.5 s for a hit |
| +0.05 s | Embers | Dots at `LightEmission` 1, Speed 10-120, Drag 10, Lifetime 0.75-2 |
| 0 | Light | A PointLight at Brightness 7-16, Range 7-15, fading over 0.5 s |

**Wind and smoke** around an impact:
- **Wind:** 3-6 nearly transparent grey arcs and rings: crescent and radial-streak textures,
  flat (`VelocityPerpendicular`), growing to 25-35 studs by 60% of life, Transparency from
  0.45-0.85 to above 1, `LightEmission` 1, `RotSpeed` ±15-20, `ZOffset` 0.5, over the smoke.
- **Smoke:** self-lit puffs in warm and grey pairs.
- **A ground skirt:** a flat copy of the smoke, squashed.
- **Black grit:** a few dark dust particles.

## Impact (melee hit, punch, slash contact)
Duration 0.3-0.6.
1. Core flash: neon disc or sphere, scale up 1 -> 6-8 while fading, 0.1-0.25s.
2. Sparks: burst 15-30, high speed, high Drag (5-8), short Lifetime (0.2-0.45), `Squash` for streaks.
3. Ring/shockwave: thin expanding ring facing ctx.CFrame, 0.2-0.3s. Mesh: Ring.
4. Light pop: PointLight, Brightness 4-8 -> 0 over ~1.5x flash time.
5. Optional dust: 3-6 large soft particles, LightEmission 0, slow, 0.5-0.8s.

## Slash (weapon swing arc)
Duration 0.2-0.4.
1. Arc: crescent mesh, Neon, oriented along the swing plane. Mesh: Crescent.
   Tween a slight scale-up (1 -> 1.15) and Transparency 0.1 -> 1. Fade fast.
2. Optional second, wider and fainter arc behind it, delayed ~0.03s.
3. Sparks shed along the arc: small burst, VelocityParallel streaks.
4. On contact: play an Impact effect at the hit point.

## Spin slash / wind vortex (AoE swing around the caster)
Duration ~0.3 for the vortex, ~1.5 with residue. See `src/shared/VFX/Effects/WindSpinSlash.luau`.
1. Vortex: 4-6 flat spinning particles (VelocityPerpendicular, tilted attachment,
   RotSpeed 800-1000), slash flipbooks played OneShot. Dark normal-blend layers under
   additive lime ones. Phase each layer's start angle (every texture's arc sits at a
   different angle in its quad) so together they form one ~180 deg crescent (an open C,
   not a closed ring); verify with VFXScrub frames. Steep tilt (~20 deg) so one side
   rises: reads as volume.
2. Flash at ~0.015-0.065: star glare + soft glow above the caster, gone by 0.07.
3. Ground: wind-ring texture lying flat (0.35-0.6s), smoke as flat haze on a Disc emitter.
4. Thin bright crescents rising out of the vortex (0.06-0.27).
5. Residue: leaves (MeshParticles), sparkles and glow spots on a Disc emitter, debris.

## Suction / gravity pull / black hole (channelled, 1-3 s)
See `src/shared/VFX/Effects/MagnetPull.luau`. Driven by a per-frame loop for `Duration`
(add the value `ctx.Wait` returns to the loop clock, never a fixed 1/60).
1. Implosion pulses every ~0.17 s, each living ~0.13 s: a translucent dome (camera-facing
   disc centred on the ground, so the ground hides its lower half) + a flat ground disc.
   They pop in ~1.25x as a faint first frame, snap to full size, then shrink to ~0.3.
2. The ring at the disc edge: a soft medium-width band (`thick ring 2`) while the pulse is
   big, cross-faded into a crisp neon ring (`thick ring 3`) as it closes. Both exactly at
   the dome's base radius; two copies of the band (1.04 R and 0.94 R) give the reference's
   ~25%-wide band. Size the fill disc so its edge hides under the band (~0.97 R), or the
   disc reads as two rings. A ring texture with a wide soft glow (`glowing ring 2`) at high
   Brightness reads as a halo, not a ring: choose ring textures by edge profile.
   If there is a core ring, make it a faint base slightly inside where each closing ring
   ends, not a second bright ring next to it. For more distinct rings: a darker fill
   (contrast) whose edge sits under the band (outside it shows a navy rim), the outer band
   copy at LightEmission ~0.85 and the overlapping inner copy at ~0.3 (two additive copies
   blow out to white), and a faint crisp ring at the peak that brightens as it closes.
3. Inward motion: specks and pale smoke wisps from an upper-hemisphere `Sphere` emitter
   (`ShapeInOut = Inward`, Lifetime ~ radius / Speed so they vanish before the centre),
   dark shards (MeshParticles with inward Acceleration), streaks skating across the floor.
4. Flicker layers on a Box volume: short-lived lightning clusters, black jagged streaks,
   thin vertical lines (FacingCameraWorldUp keeps them upright).
5. Optional core: a star opens it (anticipation: swell while spinning fast, a smaller star
   counter-spinning inside, a glow + light building up, then snap shut into a bright pop
   as the pull starts), then a dark ball (flipbook core raised half its
   size off the ground so the ground cuts only its bottom), a faint ring at its base, looping
   wisp strands circling it and arcs flashing per pulse. For a bold, fully dark core put a
   dark `Neon` Ball part inside the flipbook (particles alone stay semi-transparent) and give
   the layers that must draw over it `ZOffset` > the ball's radius. To make a ring around the
   core visibly spin, use flat crescent strokes (`Crescent32`) with RotSpeed: a symmetric
   ring texture can't show rotation.

## Projectile (fireball, energy bolt)
Persistent while flying, plus an impact on hit. Studied heads, ribbons, paths and volleys:
`motion.md`, which wins where this list differs.
1. Head: one sprite (a `VelocityParallel` diamond aimed along the path, or a camera-facing
   core), cleared at impact.
2. Ribbons: 2-3 textured Trails (a sharp one ~0.6 s with a gap behind the head, a soft one
   ~0.85 s, a tendril ~0.3 s; shorter on a fast straight shot), `Lifetime` divided by
   `ctx.TimeScale`.
3. Shed particles: Rate 30-60, small, inherit some velocity (`VelocityInheritance` 0.2-0.4).
4. On hit: play an Impact effect at the hit point.

## Aura (buff, charge-up, status)
Looping until stopped. The cross-fade stack, size ladder and orb skeleton: `motion.md`.
1. Base glow: Highlight or ground disc, low alpha, slow pulse (tween loop 0.8-1.5s).
2. Rising particles: Rate 10-25, upward Acceleration, long Lifetime (1-2).
3. Accent: occasional bright sparks, Rate 3-8.
Keep total under budget; auras are on screen for a long time. Avoid mesh particles here.

## Explosion
Duration 0.8-1.5. Studied anatomy (flash, boiling fire body, burn-out, smoke) and the
layer numbers: `explosions.md`. A finisher should keep growing in mass for 0.25-1.35 s after
the flash while its brightness falls (`design.md` section 6).
1. Flash: very bright, very short (0.05-0.1s).
2. Fireball: large particles, quick growth then shrink, orange -> red -> dark.
3. Shockwave: expanding ground ring or flared wall. Mesh: Ring or Tube.
4. Debris: MeshParticles.Burst with rocks, gravity (Acceleration y -80 to -110),
   10-20 pieces. Mesh: Rock (2-3 seeds). Add texture-particle sparks too.
5. Smoke: dark, slow, large, LightEmission 0, 1-1.5s, rises slightly.
6. Light pop: larger range, longer fade.

### Stylized cartoon explosion (fireball balls)
See `src/shared/VFX/Effects/FireballExplosion.luau`. Real time ~3.6 s (Play returns at ~2.9 s).
1. Starburst flash 0-0.05 s (orange spikes, white core on top, ZOffset clear of the ground).
2. Balls (SmoothSphere) burst out of a small core at 0.03 s and reach full size by 0.05 s,
   then keep swelling ~25%. Update them every rendered frame (`ctx.Wait(1/240)`), or the
   20 ms burst lags in slow-mo. Colour timeline: white
   until ~0.12 s, cream with faint spots at 0.2 s, orange with big blotches at 0.3 s. The
   lower balls go dark maroon with bright rims by ~0.42 s; the top two hold the spotted
   orange ~0.1 s longer, then show large glowing lava patches before they dissolve. Never pure black. Drop the rim glow quickly once a ball is dark,
   or it reads as glass.
3. 0.03-0.25 s: a soft grey ring for the shock dome (no fill: centred on the ground it
   reads as an arc), a diffuse orange bloom, a tight floor glow, flat spiky floor rays,
   dark radial dust and dash sparks. Keep the PointLight weak (Brightness ~1, Range ~10),
   or it floods the floor.
4. Comets from ~0.035 s at ~28 studs/s with a slight droop: a thin smoke ribbon, a flame
   over the last 0.05-0.15 s of path, and a small hot head glow.
5. 0.42 s: a dark gas dome puffs out under the top balls in ~0.06 s (stacked, flattened
   camera-facing discs centred above the ground, a lit rim and two glowing band arcs in
   front). It swallows the lower balls, the bands fade by ~0.95 s and the dome thins out
   0.9-1.2 s.
6. 0.6-0.8 s: the top balls dissolve bottom-up (melt texture frames, fast-fading body).
7. Lava cracks 0.78-3.6 s (orange to ~3 s, deepening to orange-red), with embers 0.3-1.8 s
   and thin grey wisps from 1.4 s until Play returns.

### Lava fissure eruption (curtain of fire from a crack)
See `src/shared/VFX/Effects/LavaEruption.luau` (rebuilt from a reference video). ~3.65 s
of flame, then crack glow to ~4.35 s. Size the big shapes off the fissure length F.
1. Precursor 0-0.6 s: streak bursts in 3 clusters (orange + near-black), grey rock chips
   (gone by ~0.4 s), upright flame bursts ~0.25 F tall in the middle 0.6 F, hollow ring
   curls, dark soft smoke plumes ~0.9 F wide shooting up fast under heavy drag (~0.7-0.8 F
   by 0.2-0.25 s, gone by ~0.4 s), embers. The crack heats up red-orange from 0.3 s.
2. Onset ~0.7 s: an orange spike row, then within ~0.035 s a dense curtain of smooth thin
   tongues 1.0 F wide, ~0.65 F tall at the edges and ~0.95 F in the centre, so the top
   tapers (about as tall as it is wide), with a soft flame body behind them from ~0.85 s.
   Wind arcs from ~0.72 s: thin, peach-red, flat ellipses 1.3-1.6 F across the base (plus
   one raised, tilted layer), gone by ~1.25 s.
3. Burn: the curtain is 0.75 F wide, around a tapered central flame ~0.45 F wide at its
   base with a yellow core low down, a dim red streak above it, a hot orange line along
   the crack, dark side tongues, curls, flecks and a few large orange embers. Saturated
   orange: yellow only low in the middle, deep red over each tongue's last 40%.
4. Die-down ~2.85-3.65 s: the curtain narrows to a bundle ~0.2 F wide while it stays
   tall. Stop emitting ~0.15 s early and shrink lifetimes so nothing lingers. The crack
   glow stays red-orange and dim.
5. Playtest tuning (Oscar's changes after the first build, now in the module):
   - Default `Scale = 2.5` (fissure ~50 studs). Oscar tried 3 first, then settled on 2.5.
   - The central column, glow, core, streak and both veil beams use `FaceCamera = false`.
     Their attachments use `CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)`
     (X up the flame, Y along the fissure).
   - Wall height: `WALL_HEIGHT = 0.85` trims the tongue and body lifetimes and the beam
     heights together. Speed: tongues and body move `TONGUE_RUSH = 1.6`× faster and live
     1/1.6 as long. The per-frame loop rewrites the tongue `Lifetime`, so the factor is
     applied there too.
   - Density: `FlameRate = 100`. The tongues are wider (`Squash` 0.3→0.6). The flame
     body has its own box at 0.9 of the curtain width, at rate `FlameRate * 0.4`,
     starting 0.25 transparent. The veil reaches 0.3 transparency at its base. The side
     tongues get `FlameRate * 0.5` each and the V phase thins them by only 25%; at 55%
     the sides showed gaps.
   - Sway: two mixed sines (`0.75 sin(5.7t) + 0.25 sin(10.1t + 1.3)`). They push every
     live tongue and body particle sideways (`Acceleration = RightVector * 1.6 B * sway`)
     and move the beam tops by `0.07 B * sway` along the fissure.
   - Wind arcs: `Speed` 1-1.2 B up with `Drag` 2.5, so they rise ~0.3 B as they spin.
     Lifetime 0.42-0.5 s, transparency 0.4 → 1, 13 arcs in total.

## Ground slam / earth ability
Duration 0.6-1.2. See `examples/GroundSlam.luau`.
1. Shockwave ring along the ground. Mesh: Ring.
2. Rock debris via MeshParticles, upward cone (Spread 45-60). Mesh: Rock.
3. Optional spikes erupting: tween Spike meshes up from below ground, hold, sink. Mesh: Spike.
4. Dust ring: soft particles, LightEmission 0.
5. Light pop.

## Ice / crystal
Duration 0.5-1.
1. Shards: MeshParticles burst or static shards tweened up from the ground. Mesh: Shard.
2. Frost mist: pale soft particles, slow.
3. Glints: a few small sparkles, LightEmission 1.

## Movement (dash, double jump, landing)
Duration 0.3-0.5.
1. Afterimage or Trail along the path.
2. Ground puff: flat ring of dust at start/landing, LightEmission 0.
3. Speed lines: few long thin particles, `Orientation = VelocityParallel`.

## Buff / Heal
Duration 0.6-1.2.
1. Upward column or spiral of soft particles. Mesh (optional): Tube with a scrolling texture.
2. Ground ring expanding and fading. Mesh: Ring.
3. Gentle Highlight flash on the character (FillTransparency 0.6 -> 1).
