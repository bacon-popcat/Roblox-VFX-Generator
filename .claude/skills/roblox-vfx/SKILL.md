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
└── Effects/        one ModuleScript per effect
ReplicatedStorage/VFX/Meshes/      published mesh templates (Studio-only, made by MeshFactory)
ReplicatedStorage/Assets/VFX/      art library (Studio-only), see references/textures.md
StarterPlayer/StarterPlayerScripts/Client   VFXHarness test bench (src/client/init.client.luau)
```

Full structure, naming, asset, sync, engine-gotcha and testing conventions:
`references/structure.md`. Read it before writing or changing any effect; its rules and
checklist are part of this skill.

Effects run on the client. Effects may require `MeshParticles`; they must never
require `MeshFactory` or `VFXScrub` (edit-time tools).

## Workflow

1. **Classify** the request: impact, slash, projectile, aura, explosion, movement
   (dash/jump), buff/heal, or ambient. Read the matching section of
   `references/recipes.md`.
2. **Read `references/style-guide.md`** and follow it over your own taste.
3. **Pick textures** from `references/textures.md`. Reuse before inventing. If nothing
   fits, say what texture you'd want and use the closest existing one for now.
4. **Meshes:** if the effect needs a mesh shape (slash arc, shockwave, spikes,
   shards, rocks), follow `references/meshes.md` before writing the effect.
5. **Write the module** using the contract and the template in `references/structure.md`.
   Base it on the closest file in `examples/`.
6. **Expose everything tunable** in `Defaults` (colors, scale, counts, timings).
   Only use attribute-safe types: number, boolean, string, Color3, Vector3.
7. **Check the budget** (below) and run the "New effect checklist" in
   `references/structure.md` before finishing. Test it as described there (VFXHarness,
   VFXScrub).
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

For many mesh pieces (debris, shards), use
`MeshParticles.Burst(ctx, template, count, config)`; see `references/properties.md`.

Rules:
- Never parent outside `ctx.Folder`.
- Never use `task.wait`, `wait`, or raw `TweenService`.
- Set `Rate = 0` on burst emitters.
- Set `CanCollide`, `CanQuery`, `CanTouch`, `CastShadow` to false on any visible part.
- Get meshes by cloning templates from `ReplicatedStorage/VFX/Meshes`. If a template might be
  missing, fall back to a plain Part (see `examples/GroundSlam.luau`).
- `Linger` must cover the longest particle or mesh-particle lifetime.

## Design principles

- **Layer it.** Good effects have 3-5 layers: a bright core flash, a primary shape
  (ring, slash, burst), secondary particles (sparks, debris), and residue (smoke,
  embers, fading glow). One emitter alone always looks cheap.
- **Fast in, slow out.** The peak should arrive in 0.03-0.1s. Fading takes 3-6x longer.
  Use `Quad`/`Exponential` Out easing for expansion.
- **Value contrast.** Near-white core, saturated mid, darker edges. A single flat
  color reads as weak.
- **Size curves pop then shrink.** Particles usually start at full size or grow
  quickly, then shrink to 0. Avoid constant size.
- **Energy vs. matter.** Energy (magic, light, fire) uses `LightEmission = 1`,
  `LightInfluence = 0`, or Neon for meshes. Matter (smoke, dust, rocks) uses
  `LightEmission = 0` and some `LightInfluence` so it sits in the scene.
- **Meshes for shapes, particles for softness.** Use meshes for crisp silhouettes
  (slashes, rings, shards, rocks) and texture particles for anything soft or
  numerous (smoke, sparks, glow).
- **Readability.** It must still read at 40 studs. Big simple shapes beat many tiny
  particles.

## Budget

Sized for detailed, layered effects. Spend it where it reads; a busy effect is not
automatically a better one.

- Texture particles: burst effects under ~400 per play. Channelled effects (a few
  seconds, e.g. `MagnetPull`) under ~200/second. Looping auras (on screen indefinitely)
  under ~80/second.
- Mesh particles: under ~60 per play and ~40 alive at once; they are full parts
  simulated on the client, far more expensive than texture particles.
- Instances created per play (emitters, attachments, anchor parts, beams, trails,
  lights; not counting particles, tweens or MeshParticles parts): under ~50.
- Meshes: under ~1000 triangles each.
- Lights: at most 2 PointLights per effect, Range 20 or less.
- Effects that can play for many players at once (replicated abilities) should
  expose their counts/rates in `Defaults` so they can be overridden lower.
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
- `examples/`: approved effects. Match their structure and quality.
  - `SlashImpact.luau`: particles + neon flash + light (no meshes).
  - `GroundSlam.luau`: mesh shockwave, MeshParticles rock debris, dust, light,
    template fallbacks.