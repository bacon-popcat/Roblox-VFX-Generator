---
name: roblox-vfx
description: Create Roblox visual effects (particles, beams, trails, flashes, lights, tweens, mesh effects, mesh debris) as effect modules for Oscar's VFXPlayer system, including generating and publishing any mesh assets the effect needs. Use this skill whenever the user asks for any visual effect, ability effect, hit effect, aura, projectile, explosion, slash, shockwave, debris, trail, glow, or "make this look cooler" in Roblox, even if they don't say "VFX".
---

# Roblox VFX

Every effect you make is a ModuleScript in `ReplicatedStorage/Shared/VFX/Effects/<EffectName>`
(on disk: `src/shared/VFX/Effects/<EffectName>.luau`, synced by Rojo) that follows the
contract below. Never write free-form VFX scripts.

## Project layout

```
ReplicatedStorage/Shared/VFX/      code, Rojo-synced from src/shared/VFX
├── VFXPlayer       plays effects by name (client-side), provides ctx
├── MeshParticles   simulates many MeshParts like particles
├── MeshFactory     authoring tool: generates + publishes meshes (Edit mode only)
├── ForgeBridge     plays VFX Forge templates for ctx.Forge (runtime only)
├── ForgeAssets/    VFX Forge templates (Models), Rojo-synced .rbxmx files
└── Effects/        one ModuleScript per effect
ReplicatedStorage/Shared/Packages/ Wally packages (ForgeVFX)
ReplicatedStorage/Assets/Meshes/   published mesh templates (Studio-only, made by MeshFactory)
ReplicatedStorage/Assets/VFX/      art library (Studio-only), see references/textures.md
StarterPlayer/StarterPlayerScripts/Client   VFXHarness test bench (src/client/init.client.luau)
```

Full structure, naming, asset, sync, engine-gotcha and testing conventions:
`references/structure.md`. Read it before writing or changing any effect; its rules and
checklist are part of this skill.

**Precedence.** Where the Roqer-derived references (`design.md`, `explosions.md`,
`motion.md`, `camera-world.md`, `drawing-textures.md`, `review.md`, the "Impact skeleton" in
`recipes.md`, and the "Mesh effects" section of `meshes.md`) disagree with anything else in
this skill (other recipes, Oscar's corrections, engine gotchas, budgets, `style-guide.md`),
follow Roqer's guidance. The effect contract and rules in `structure.md` (ctx, Defaults,
`ctx.Folder`, no `task.wait`) are how our code runs, not design guidance, and still apply:
when Roqer's guidance needs something they forbid, extend `VFXPlayer`/`ctx` first, as Roqer
says to extend its own emit module.

Effects run on the client. Effects may require `MeshParticles`; they must never
require `MeshFactory` or `VFXScrub` (edit-time tools), nor `ForgeBridge` or ForgeVFX
(play Forge templates with `ctx.Forge`).

## Workflow

1. **Classify** the request: impact, slash, projectile, aura, explosion, movement
   (dash/jump), buff/heal, or ambient, and name its role (a frequent basic skill, an
   ultimate, a buff...): the role sets its scale. Read the matching section of
   `references/recipes.md`, and `references/design.md` (palette, value, brightness against
   the place's bloom, layering, the intensity curve). Add the topic files the effect needs:
   `references/explosions.md` (fire, smoke, blasts), `references/motion.md` (projectiles,
   slashes, beams, trails, auras, orbs), `references/camera-world.md` (camera, screen,
   lights, craters).
2. **Read `references/style-guide.md`** for the game's look (Roqer's guidance wins where
   they disagree; see Precedence).
3. **Textures:** most effects should draw their own (`references/drawing-textures.md`):
   flipbooks, crisp shapes and light with numpy (`tools/vfx/vfxtex.py`), checked with
   `tools/vfx/flipbook.mjs`. Use a library texture (`references/textures.md`) when one
   already matches the effect's style; Google Gemini through Composio (Pro model for
   detail) or ComfyUI for painted images numpy can't draw. Built-in `rbxasset://` textures
   are stand-ins for blocking out only.
4. **Meshes:** if the effect needs a mesh shape (slash arc, shockwave, spikes,
   shards, rocks), follow `references/meshes.md` before writing the effect.
   **Forge:** if the effect is authored in VFX Forge, or needs Forge mesh VFX, bezier
   projectiles, lightning or ground shockwaves, play those layers from a Forge template
   with `ctx.Forge` ("VFX Forge layers" in `references/structure.md`). Otherwise stay in Luau.
5. **Write the module** using the contract and the template in `references/structure.md`.
   Take the design from the references, not from other effects' modules; use `examples/`
   only for the contract's shape (ASSETS, Defaults, Linger, ctx timing).
6. **Expose everything tunable** in `Defaults` (colors, scale, counts, timings).
   Only use attribute-safe types: number, boolean, string, Color3, Vector3.
7. **Check the budget** (below) and run the "New effect checklist" in
   `references/structure.md` before finishing. Test it as described there (VFXHarness,
   VFXScrub) and judge the captures with `references/review.md`: from close and from the
   player's camera, with the colour check (`tools/vfx/clip.mjs tone`). To match a reference
   video, read it with `tools/vfx/clip.mjs` ("Matching a reference video" in
   `references/structure.md`).
8. **Report** in 2-3 sentences: what layers the effect has and which Defaults to
   tweak first. Mention any new meshes you published.

## Effect contract

```luau
local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 170, 60),
	Scale = 1,
	-- every tunable value goes here
}

Effect.Linger = 0.8 -- seconds kept alive after Play returns (let particles die)

function Effect.Play(ctx)
	local p = ctx.Params
	-- build the effect here
end

return Effect
```

`ctx` provides:

| Field | Use |
|---|---|
| `ctx.CFrame` | Where the effect plays. LookVector points toward the viewer/attacker. |
| `ctx.Params` | Defaults merged with overrides. Always read values from here. |
| `ctx.Folder` | Parent everything here. It is destroyed automatically. |
| `ctx.TimeScale` | Current playback speed (slow-mo in the harness). Read-only. |
| `ctx.Anchor(cf?)` | Invisible anchored part for attachments, emitters, lights. |
| `ctx.Emit(emitter, n)` | Burst particles. Always use this, not `:Emit()`, so slow-mo works. |
| `ctx.Tween(inst, t, props, style?, dir?)` | Tween in effect time. |
| `ctx.Wait(t)` | Wait in effect time; returns the effect time that actually passed (add that to per-frame loop clocks). Never use `task.wait` directly. |
| `ctx.Shake(magnitude, duration, options?)` | Shake the local camera (degrees, effect seconds; rotation only, distance-gated, never drifts). Magnitudes: `references/camera-world.md`. |
| `ctx.Forge(template, cf?, options?)` | Play a VFX Forge template from `Shared.VFX.ForgeAssets` as a layer (retimed for slow-mo; `options.Scale` / `options.Color`). Non-blocking, returns Forge's env. Only when the effect needs Forge: see "VFX Forge layers" in `references/structure.md`. |

For many mesh pieces (debris, shards), use
`MeshParticles.Burst(ctx, template, count, config)`; see `references/properties.md`.

Rules:
- Never parent outside `ctx.Folder`.
- Never use `task.wait`, `wait`, or raw `TweenService`.
- Set `Rate = 0` on burst emitters.
- Set `CanCollide`, `CanQuery`, `CanTouch`, `CastShadow` to false on any visible part.
- Get meshes by cloning templates from `ReplicatedStorage/Assets/Meshes`. If a template might be
  missing, fall back to a plain Part (see `examples/GroundSlam.luau`).
- `Linger` must cover the longest particle or mesh-particle lifetime.

## Design principles

- **Size it for its role and its viewer.** A hit of many is 10-13 studs; a whole-skill
  projectile's payoff or a finisher is 40-300, seen from where the player stands
  (`references/design.md`).
- **Palette first.** About five colours, nothing outside them; saturated energy,
  desaturated matter, a complementary accent on ~10% of layers at most.
- **Many layers, one sprite each.** A studied hit has 40-60 distinct layers, mostly single
  sprites stacked and timed in place: flash, impact stars with black and white twins, black
  backing, streaks, ring, fire body, smoke, embers, light (`references/recipes.md`, "Impact
  skeleton"). One emitter alone always looks cheap.
- **Intensity only goes down.** Fire once, let layers die at different times; nothing gets
  brighter again. A finisher's mass still grows for 0.25-1.35 s after its flash, carried by
  body flipbooks (crescents, tongues, puffs), not sparks.
- **Fast in, slow out.** The flash fires at 0 and lasts 0.03-0.15 s; every other layer
  follows at +0.03 s or later, in 0.025-0.05 s steps. Use `Quad`/`Exponential` Out easing for
  expansion.
- **Value contrast.** Near-white core, saturated mid, darker edges. A single flat
  color reads as weak. Darks come from black backing, black twins and dark gradient tails;
  white is a thin shape (ring, flare, crescent), never a filled blob.
- **Size curves pop then shrink.** Particles usually start at full size or grow
  quickly, then shrink to 0. Avoid constant size.
- **Solid colour, additive highlights.** Colour sits on solid layers (`LightEmission` 0.3
  or less, or negative for a dark rim) at Brightness 5-55; additive (`LightEmission = 1`) is
  for thin highlights and small glows, or an effect washes out to pastel over a bright sky.
  `LightInfluence = 0` on energy and on most smoke (self-lit smoke keeps its grey in shade).
  Read the place's Bloom before choosing Brightness.
- **Meshes for shapes, particles for softness.** Use meshes for crisp silhouettes
  (slashes, rings, shards, rocks) and texture particles for anything soft or
  numerous (smoke, sparks, glow).
- **Readability.** It must still read at 40 studs. Big simple shapes beat many tiny
  particles.

## Budget

Sized for detailed, layered effects. Spend it where it reads; a busy effect is not
automatically a better one.

- Texture particles: a few hundred per effect is fine; studied hits stay there by emitting
  one or a few sprites per layer. The engine guide caps emission near 400 a second (100 on
  mobile). Looping auras (on screen indefinitely) much leaner.
- Mesh particles: under ~60 per play and ~40 alive at once; they are full parts
  simulated on the client, far more expensive than texture particles.
- Emitters: studied hits use 40-60 emitters for a moment that lasts a second; every emitter
  is a draw call, so keep always-on effects much leaner. Share attachments between them.
- Meshes: under ~1000 triangles each.
- Lights: one PointLight per hue, flashed then faded (Range may grow to 35-40 while its
  Brightness falls; keep it short enough to mark the spot, `references/camera-world.md`).
- Effects that can play for many players at once (replicated abilities) should
  expose their counts/rates in `Defaults` so they can be overridden lower.
- Effects that fire constantly (muzzle flashes, footsteps) should be pooled rather than
  rebuilt every play; a pool resets every changed property before reuse. VFXPlayer builds
  each play fresh, which is right for occasional effects.
- A LocalScript can read
  `UserSettings():GetService("UserGameSettings").SavedQualityLevel` and pass lower counts
  through overrides at low settings (automatic quality doesn't expose its level).
- Every emitter is a draw call, and cost grows with screen coverage: large overlapping
  transparent layers cost more than many small ones. Keep always-on effects much leaner
  than a one-second hit.
- If over budget, cut the least visible layer first.

## Reference files

- `references/structure.md`: code layout (disk <-> Studio), effect module template, ctx
  API, naming, asset conventions, engine gotchas, rules, testing, new-effect checklist,
  open issues.
- `references/recipes.md`: layer breakdowns and timings for each effect category.
- `references/properties.md`: properties that matter, good starting values, and the
  MeshParticles config.
- `references/textures.md`: available textures and what each is for.
- `references/meshes.md`: reusing, generating, previewing, and publishing meshes.
- `references/style-guide.md`: this game's look. Overrides general advice.
- `references/design.md`: studied palette, value, brightness/bloom, layers, orientation,
  timing and motion numbers.
- `references/explosions.md`: fire bodies, burn-out, smoke.
- `references/motion.md`: projectiles, volleys, slashes, dashes, held beams, beams and
  trails, auras, orbs.
- `references/camera-world.md`: FOV, blur, impact frames, shake, lights, craters, cast pose.
- `references/drawing-textures.md`: what good textures look like; drawing, checking and
  uploading textures and flipbooks.
- `references/review.md`: how to look at an effect and what to ask of every capture.
- `tools/vfx/` (repo root): `clip.mjs` (reference clips, compare sheets, colour check),
  `flipbook.mjs`, `vfxtex.py`, `examples.py`. AGPL-3.0, ported from Roqer
  (https://github.com/S4US/Roqer), whose VFX skill the design/explosions/motion/
  camera-world/drawing-textures/review references are adapted from.
- `examples/`: approved effects. Match their structure and quality. The larger approved
  effects live in `src/shared/VFX/Effects/` (not copied here, so they never go stale); read the
  closest one before writing a similar effect:
  - `ChromaticStrike.luau`: ranged strike rebuilt from a reference. Spline projectiles with
    star heads and layered beam trails, a dash with a spinning head, a camera-locked screen
    vignette, `ctx.Shake`, a long burn driven by a time-sorted event list, custom textures.
  - `LavaEruption.luau`: fissure eruption; per-frame channel rates, upright beam sheets,
    SurfaceGui crack decals, pulsing layers measured on 60 fps strips.
  - `FireballExplosion.luau`: cartoon explosion; textured SmoothSphere balls that cool and
    dissolve through texture frames, a gas dome from stacked particles, comet beams.
  - `MagnetPull.luau`: channelled suction; inward Sphere emitters, implosion pulses, a dark
    core with a Neon ball, MeshParticles shards.
  - `WindSpinSlash.luau` / `WindBladeTrail.luau` / `WindSpinSlashCombo.luau`: a spin slash from
    phased flipbook layers, a weapon trail, and a composite effect calling child effects.
  - `SlashImpact.luau`: particles + neon flash + light (no meshes).
  - `GroundSlam.luau`: mesh shockwave, MeshParticles rock debris, dust, light,
    template fallbacks.