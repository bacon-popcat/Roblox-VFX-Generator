# Recipes

Timings are in effect seconds. Layers are listed in draw-priority order.
"Mesh:" notes name the MeshFactory generator to use (see `meshes.md`).

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

## Projectile (fireball, energy bolt)
Persistent while flying, plus an impact on hit.
1. Core: small bright sphere or glow particle, `LockedToPart = true`.
2. Trail: Trail with WidthScale tapering to 0, Lifetime 0.15-0.3.
3. Shed particles: Rate 30-60, small, inherit some velocity (`VelocityInheritance` 0.2-0.4).
4. On hit: play an Impact effect at the hit point.

## Aura (buff, charge-up, status)
Looping until stopped.
1. Base glow: Highlight or ground disc, low alpha, slow pulse (tween loop 0.8-1.5s).
2. Rising particles: Rate 10-25, upward Acceleration, long Lifetime (1-2).
3. Accent: occasional bright sparks, Rate 3-8.
Keep total under budget; auras are on screen for a long time. Avoid mesh particles here.

## Explosion
Duration 0.8-1.5.
1. Flash: very bright, very short (0.05-0.1s).
2. Fireball: large particles, quick growth then shrink, orange -> red -> dark.
3. Shockwave: expanding ground ring or flared wall. Mesh: Ring or Tube.
4. Debris: MeshParticles.Burst with rocks, gravity (Acceleration y -80 to -110),
   10-20 pieces. Mesh: Rock (2-3 seeds). Add texture-particle sparks too.
5. Smoke: dark, slow, large, LightEmission 0, 1-1.5s, rises slightly.
6. Light pop: larger range, longer fade.

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
