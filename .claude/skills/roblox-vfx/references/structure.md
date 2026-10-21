# VFX code structure

Part of the `roblox-vfx` skill (`.claude/skills/roblox-vfx/references/structure.md`): the
authoritative guide to where VFX code lives, how it is organized, and how to test it. How to
*design* an effect (layers, values, recipes) lives in `SKILL.md` and the other
`references/`. Read both before writing an effect. Paths like `references/x.md` are relative
to the skill folder; `src/...` paths are relative to the repo root.

## Layout

Disk is the source of truth for code. `rojo serve` syncs `src/` into Studio live; edits
made to synced scripts inside Studio are overwritten. Edit files on disk only. If the
Rojo plugin in Studio is not connected, nothing syncs: connect it (or push the changed
module's `Source` yourself and checksum it) before testing. Keep the Rojo plugin's
two-way sync **off**: with it on, Studio's copy of a script is written back to disk every
couple of seconds and silently reverts disk edits Rojo hasn't pushed yet.

```
VFX/                                  (repo root)
├── default.project.json              Rojo tree (below)
├── CLAUDE.md                         project instructions (points here)
├── .claude/skills/roblox-vfx/        skill: SKILL.md, references/*.md (this file:
│                                     references/structure.md), examples/*.luau
├── tools/vfx/                        dev-machine tools (Node/Python, AGPL from Roqer): clip.mjs
│                                     (reference clips, compare, colour check), flipbook.mjs,
│                                     vfxtex.py + examples.py (drawn textures); see its README
├── assets/textures/                  drawn texture sources (<Name>.py) and their PNGs
└── src/
    ├── shared/VFX/
    │   ├── VFXPlayer.luau            plays effects by name, builds ctx
    │   ├── MeshParticles.luau        MeshPart "particles" (client sim)
    │   ├── MeshFactory.luau          edit-time mesh generator/publisher
    │   ├── VFXScrub.luau             edit-time freeze-frame player for screenshots
    │   ├── VFXCamera.luau            locks the camera on an effect at fixed angles (side/top/3/4)
    │   ├── ForgeBridge.luau          plays VFX Forge templates for ctx.Forge
    │   ├── ForgeAssets/<Name>.rbxmx  VFX Forge templates (Models), see "VFX Forge layers"
    │   └── Effects/<Name>.luau       one ModuleScript per effect
    ├── shared/Packages/              Wally packages (ForgeVFX), written by `wally install` and committed
    ├── shared/WindSword/             Wind Sword timings (init.luau) + Slash RemoteEvent (Slash.model.json)
    ├── client/
    │   ├── init.client.luau          VFXHarness test bench (Studio + live place)
    │   └── WindSwordReplicator.client.luau   plays other players' Wind Sword slashes
    ├── server/
    │   ├── init.server.luau          placeholder
    │   └── WindSwordServer.server.luau       validates and relays Wind Sword slashes
    └── starterpack/WindSword/        the Wind Sword Tool (init.meta.json, Handle, WindSwordClient)
```

| Disk | Studio | Class |
|---|---|---|
| `src/shared/VFX/VFXPlayer.luau` | `ReplicatedStorage.Shared.VFX.VFXPlayer` | ModuleScript |
| `src/shared/VFX/MeshParticles.luau` | `ReplicatedStorage.Shared.VFX.MeshParticles` | ModuleScript |
| `src/shared/VFX/MeshFactory.luau` | `ReplicatedStorage.Shared.VFX.MeshFactory` | ModuleScript |
| `src/shared/VFX/VFXScrub.luau` | `ReplicatedStorage.Shared.VFX.VFXScrub` | ModuleScript |
| `src/shared/VFX/VFXCamera.luau` | `ReplicatedStorage.Shared.VFX.VFXCamera` | ModuleScript |
| `src/shared/VFX/ForgeBridge.luau` | `ReplicatedStorage.Shared.VFX.ForgeBridge` | ModuleScript |
| `src/shared/VFX/ForgeAssets/<Name>.rbxmx` | `ReplicatedStorage.Shared.VFX.ForgeAssets.<Name>` | Model (Forge template) |
| `src/shared/Packages/ForgeVFX.lua` | `ReplicatedStorage.Shared.Packages.ForgeVFX` | ModuleScript (Wally link to the ForgeVFX package) |
| `src/shared/VFX/Effects/<Name>.luau` | `ReplicatedStorage.Shared.VFX.Effects.<Name>` | ModuleScript |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` | LocalScript |
| `src/server/init.server.luau` | `ServerScriptService.Server` | Script (calls `ForgeVFX.init()` for Forge's collision groups) |
| `src/shared/WindSword/` | `ReplicatedStorage.Shared.WindSword` (+ `.Slash` RemoteEvent) | ModuleScript |
| `src/client/WindSwordReplicator.client.luau` | `StarterPlayer.StarterPlayerScripts.Client.WindSwordReplicator` | LocalScript |
| `src/server/WindSwordServer.server.luau` | `ServerScriptService.Server.WindSwordServer` | Script |
| `src/starterpack/WindSword/` | `StarterPack.WindSword` | Tool (Handle part, `WindSwordClient` LocalScript) |
| (not on disk) | `ReplicatedStorage.Assets.Meshes` | Folder of MeshFactory templates |
| (not on disk) | `ReplicatedStorage.Assets.VFX` | Art library (asset cards) |
| (runtime) | `Workspace.ActiveVFX.<Name>` | `ctx.Folder`, one per play |
| (edit time) | `Workspace.VFXScrub` | `ctx.Folder` of a VFXScrub freeze-frame; `Clear()` removes it |
| (runtime, harness) | `Workspace.VFXHarnessConfig`, `Workspace.VFXTarget`, `PlayerGui.VFXHarness` | |

Rojo rules that matter here:
- File name = instance name. `.luau` = ModuleScript, `.client.luau` = LocalScript,
  `.server.luau` = Script. `init.*.luau` turns its folder into that script, so any other
  file in `src/client/` becomes a child of the `Client` LocalScript (a `.luau` file a child
  ModuleScript, a `.client.luau` file a child LocalScript).
- Folders mapped with `$path` are Rojo-owned: Rojo can delete instances that aren't on
  disk. Never store Studio-made content (mesh templates, assets) under `Shared`,
  `Client`, or `Server`. Studio-only content goes in `ReplicatedStorage.Assets`
  (`Assets.VFX` = art library, `Assets.Meshes` = mesh templates).

## Runtime flow

```luau
local VFXPlayer = require(game:GetService("ReplicatedStorage").Shared.VFX.VFXPlayer)
VFXPlayer.Play("SlashImpact", hitCFrame, { Color = Color3.fromRGB(120, 200, 255) })
```

`Play(name, cframe, overrides)` requires `Effects.<name>` once (cached), merges
`Defaults` with `overrides` into `ctx.Params`, and runs `Effect.Play(ctx)` in a new
thread. Errors are caught and warned (`VFXPlayer: effect '<name>' errored`). When `Play`
returns, it waits `Linger` (effect time) and destroys `ctx.Folder`. `VFXPlayer.TimeScale`
is read once per play; `VFXPlayer.Clear()` removes everything. Call it from the client
only. Server-triggered effects need a RemoteEvent (the Wind Sword's `Slash` is the one
example). The server decides that something happened and fires the effect's name and a
CFrame; each client plays it. Prefer an `UnreliableRemoteEvent` for pure presentation: it
drops payloads over 1000 bytes, so send names and numbers, never instances. Never let damage
or rewards wait on an effect. To time an effect to an animation, play it from the track's
`GetMarkerReachedSignal("<Marker>")` on the hit keyframe rather than a fixed delay.

**Instance overrides.** Overrides can carry instances (e.g. the sword part), which can't
be `Defaults` (attributes): `VFXPlayer.Play("WindBladeTrail", root.CFrame, { Weapon = blade })`.
Document such runtime-only keys in the effect's header and always handle them being nil.

**Composite effects.** An effect may require sibling effects and call their `Play` with a
child ctx (see `WindSpinSlashCombo`): `setmetatable({ Params = params }, { __index = ctx })`
shares the folder, clock and helpers. Set `Linger` to the max of the children's. In a real
game prefer firing the parts from animation events (windup start, hit frame) so they stay
in sync with the animation.

### Wind spin-slash move

| Effect | Plays | Notes |
|---|---|---|
| `WindBladeTrail` | during the windup | `Weapon` override = blade part (`BladeBase`/`BladeTip` attachments optional); `Duration` = time to the hit frame. Without a weapon it builds a stand-in katana. |
| `WindSpinSlash` | on the hit frame | `ctx.CFrame` = caster root. |
| `WindSpinSlashCombo` | both, back to back | Harness preview of the full move. |

The playable version is the **Wind Sword** tool (`src/starterpack/WindSword`, every player
spawns with it). Clicking plays `WindSpinSlashCombo` with `Weapon = Handle` and the
default tool slash animation, then fires `Shared.WindSword.Slash`; the server
(`src/server/WindSwordServer.server.luau`) checks equip + cooldown and relays it, and
`src/client/WindSwordReplicator.client.luau` plays it for everyone else. Timings live in
`src/shared/WindSword/init.luau`. The blade runs along the Handle's -Z axis (tip
attachment `BladeTip`); keep `Tool.Grip` and the attachments in sync if you resize it.

### Magnet pull

`MagnetPull`: purple gravity suction centred on the ground below `ctx.CFrame`. With
`BlackHole` (default on), a spinning star (`FlashSize`, `FlashTime`, `FlashSpin`, with a
counter-spinning inner star and a flare) opens it and snaps shut at `FlashOpen`, when the
pull starts with a burst of bolts and black streaks, and a dark swirling core
(`CoreSize`) with a neon ring holds in the centre while bright arcs flash with each pulse.
The pull runs for `Duration` (default 1.5 s): a translucent dome + ground disc (soft
magenta band closing into a crisp neon ring) pop in at `Radius` and shrink into the centre
every `PulseInterval`, while dark shards (MeshParticles), specks, smoke wisps
(`WispRate`), floor streaks (`StreakRate`), lightning, black streaks and thin lines are
pulled in. The core is a solid dark Neon ball inside a swirling flipbook core, with wisp
strands and flat crescent strokes spinning around it (`CoreSpinSpeed`) and a faint pink
ring at its base.
`BlackHole = false` gives the suction only.

### Fireball explosion

`FireballExplosion`: stylized cartoon explosion on the ground below `ctx.CFrame`. Play
returns at ~2.9 s; the cracks fade by ~3.6 s and the last wisps by ~4.3 s.
1. A starburst flash bursts into a cluster of six balls that fly out of a small core in
   ~0.03 s. The balls cool from white-hot, through
   cream and orange with big blotchy spots, into dark maroon balls with glowing rims and
   lava patches.
2. The four lower balls sink into a dark gas dome (particles only, no mesh). It is
   built from stacked, flattened, camera-facing discs centred above the ground, a lit rim
   and two glowing `BandArc` bands in front, and it puffs out in ~0.06 s at `GasStart`.
3. The two top balls dissolve quickly (`CrumbleStart`/`CrumbleTime`, 0.6-0.8 s): their
   shell steps through the `FireMelt` textures while the body fades. The gas dome thins
   out by ~1.2 s.
4. The supporting layers: three fire comets (one Beam each, bent into their flight
   parabola), sparks, a faint shock dome, floor glow/rays/radial dust, lava cracks
   (`CrackStart`, `CrackTime`), embers, haze and smoke wisps.

Timeline Defaults: `CoolTime`, `TopDelay`, `SinkTime`, `GasStart`/`GasTime`,
`CrumbleStart`/`CrumbleTime`. Spot, lava and melt colours are baked into their
textures. The module preloads its custom textures from a top-level `task.spawn` +
`pcall(ContentProvider.PreloadAsync)`. That doesn't yield the require, so it is allowed.

### Lava eruption

`LavaEruption`: a lava fissure on the ground below `ctx.CFrame`, running across the view
(along its RightVector). Plain Luau, no Forge. `WallLength` (the fissure, 20 studs) sizes
the fissure, curtain, wind, column and smoke spread; `Scale` (default 2.5) sizes everything. Play returns when the crack has faded, at ~4.35 s.
1. 0-0.6 s precursor: three streak clusters, flung rocks, upright flame bursts, ring
   curls, dark smoke that shoots up to ~0.7 `WallLength` by 0.2 s, and embers. The crack
   (three Top-face SurfaceGuis: a dark rift, a bright orange rift line and a faint red
   pool) heats up from 0.3 s.
2. 0.70 s (`EruptTime`): a spike row, then a curtain of flame tongues is up within
   ~0.035 s. The tongues are in three bands whose boxes follow the curtain width: the edges
   reach ~0.65 `WallLength` and the centre band, 1.3x taller, ~0.95. Tongues turn deep red
   over the last 40% of their life. They come with a soft flame body, two faint scrolling beam
   veils, wind arcs (flat on the ground plus a raised, tilted layer) and a hot ground line.
3. From ~0.82 s: a tapered central flame (beam) with a yellow core, a glow and a dim red
   streak above it. The curtain holds at 0.75 `WallLength` wide, with opaque dark tongues
   alternating at its edges (they reuse the precursor burst box).
4. From 2.85 s (`EruptTime` + `BurnTime`): the edge bands stop and the centre narrows to
   a thin bundle. Emission stops ~0.15 s before `FadeTime` ends, and the tongue lifetime
   shrinks so nothing lingers.

One per-frame loop (`ctx.Wait(1/240)`) drives the bursts (one per step), channel rates,
emitter box widths, beam widths, the light and the crack. Instances: ~49.

## VFX Forge layers

[ForgeVFX](https://github.com/zilibobi/forge-vfx) is the emit module of the VFX Forge
plugin, installed with Wally (`wally.toml`; `wally install` writes `src/shared/Packages`).
It plays effects authored as data: instances whose Forge attributes (`EmitDelay`,
`EmitCount`, `EmitDuration`, `EffectDuration`, `Width0_End`, mesh `Start`/`End` parts,
`BezierParticle`/`LightningBolt`/`Shockwave` tags...) describe the timeline.

**When to use it.** Only when the effect needs something Forge does and our code doesn't:
an effect authored in the Forge plugin (or a Forge reference being reproduced), Forge
mesh VFX (Start/End tweens with decals on the mesh), bezier projectiles, lightning bolts,
ground shockwave rings/lines/debris. Procedural effects stay plain Luau: the existing
effects don't use Forge, and a layer that is simple in Luau shouldn't move to Forge.

**Templates.** A Forge template is a Model saved as `src/shared/VFX/ForgeAssets/<Name>.rbxmx`
(Rojo syncs it to `Shared.VFX.ForgeAssets.<Name>`). Its pivot is the effect origin (on
the ground, LookVector toward the viewer, like `ctx.CFrame`), its children are the Forge
items, and nothing in it is Studio-only. Invisible host parts: `Transparency = 1`,
`Anchored`, and `CanCollide`/`CanQuery`/`CanTouch`/`CastShadow` false. Edit a template on
a copy in Studio with the Forge plugin, then save it back over the `.rbxmx` (right-click >
Save to File); Rojo overwrites edits made to the synced copy. Name templates after their
role (`LavaEruption`, `LavaEruptionCrack`). Don't `cacheAttributes` a template.

**Playing.** Look the template up without yielding and sequence layers with `ctx.Wait`
(this replaces Forge's folder `Stagger` and custom sequence scripts):

```luau
local forgeAssets = script.Parent.Parent:FindFirstChild("ForgeAssets")
local crackTemplate = forgeAssets and forgeAssets:FindFirstChild("LavaEruptionCrack")

function Effect.Play(ctx)
	local p = ctx.Params
	if crackTemplate then
		ctx.Forge(crackTemplate, ctx.CFrame, { Scale = p.Scale })
	else
		warn("LavaEruption: ForgeAssets.LavaEruptionCrack is missing")
	end
	ctx.Wait(p.EruptDelay)
	-- ...
end
```

`ctx.Forge` (via `ForgeBridge`) clones the template, scales it (`Model:ScaleTo` plus the
mesh scales, light ranges and Forge size attributes it misses), recolors it with Forge's
`recolor` if `Color` is given, retimes it to `ctx.TimeScale` with Forge's `retime` (plus
looping flipbook framerates), parents it to `ctx.Folder` and emits its children. Forge
timings live in the template's attributes, so expose only the knobs the effect needs in
`Defaults` (delays between layers, `Scale`, optional `Color`). To tune a Forge value per
play, clone the template yourself, set the attribute or property on the clone (never on
the template) and pass the clone to `ctx.Forge`.

**License (VFX-DL 1.1).** ForgeVFX may run only in game runtime (including Studio
playtests), not in plugins, edit-time tools or test tooling. `ForgeBridge` loads it lazily
on a running client only; the server loads it for `init()`. `VFXScrub` in Edit mode skips
Forge layers with a warning, so preview Forge effects in Play mode with the VFXHarness.
Never require ForgeVFX from `MeshFactory`, `VFXScrub` or MCP/command-bar snippets.

## Effect module contract

Base new effects on this template. Order: header, requires, `ASSETS`, constants,
local helpers, `Effect`, `Defaults`, `Linger`, `Play`, `return`.

```luau
-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/<EffectName>
-- <What it looks like, one line.> Layers: <core>, <shape>, <secondary>, <residue>.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles")) -- only if used

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	CoreGlow = "rbxassetid://0", -- StaticVFXTextures/<CardName>
	WindSheet = "rbxassetid://0", -- FlipbookTextures/<CardName> (cell 256 -> Grid4x4)
	StreakBeam = "rbxassetid://0", -- MigratedBeams/<CardName>
	SwirlMesh = { -- MigratedMeshes/<CardName>
		MeshId = "rbxassetid://0",
		TextureId = "rbxassetid://0",
		Scale = Vector3.new(1, 1, 1),
	},
}

local function makeBurstEmitter(parent, texture) -- local helpers: camelCase
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Texture = texture
	emitter.Parent = parent
	return emitter
end

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 170, 60),
	Scale = 1,
	-- every tunable value: PascalCase keys, attribute-safe types only
}

Effect.Linger = 0.8 -- effect seconds kept alive after Play returns

function Effect.Play(ctx)
	local p = ctx.Params
	-- build layers under ctx.Folder / ctx.Anchor(); time them with ctx.Wait
end

return Effect
```

The module's top level must not yield on or error over anything Studio-only: the harness
requires every effect at startup, and one bad module stops it.

## ctx API

| Field | Type | Use |
|---|---|---|
| `ctx.CFrame` | CFrame | Where to play. LookVector points toward the viewer/attacker. |
| `ctx.Params` | table | `Defaults` merged with overrides. Always read values from here. |
| `ctx.Folder` | Folder | Parent everything here (`Workspace.ActiveVFX.<Name>`). Auto-destroyed. |
| `ctx.TimeScale` | number | Playback speed for this play (slow-mo). Read-only. |
| `ctx.Anchor(cf?)` | -> Part | Invisible anchored part in `ctx.Folder` (default `ctx.CFrame`) for attachments, emitters, lights. |
| `ctx.Emit(emitter, n)` | | Burst `n` particles; sets `emitter.TimeScale`. Use instead of `:Emit()`. |
| `ctx.Tween(inst, t, props, style?, dir?)` | -> Tween | Tween in effect time. Default `Quad` / `Out`. |
| `ctx.Wait(t)` | -> number | Yield in effect time. Returns the effect time that actually passed (often more than `t`: a 1/60 wait usually takes 1-2 frames). Per-frame loops should add the return value, not `t`, to their clock. |
| `ctx.Forge(template, cf?, options?)` | -> env | Play a VFX Forge template as a layer at `cf` (default `ctx.CFrame`), retimed to `ctx.TimeScale`. Non-blocking; `env.Finished:await()` waits for it. `options`: `{ Scale = n, Color = Color3, ColorMode = "multiply" or "replace" }`. See "VFX Forge layers". |

`MeshParticles.Burst(ctx, template, count, config)`: non-blocking mesh debris; config in
`references/properties.md`.

## Naming

- **Effects:** PascalCase, describing what it looks like or does: `WindSpinSlash`,
  `GroundSlam`, `SlashImpact`. Not the owner (`RangerUlt`) and no versions (`SlashV2`).
  File name = module name = the name passed to `VFXPlayer.Play`.
- **Locals and helpers:** camelCase verbs for functions (`makeBurstEmitter`, `spawnRing`),
  camelCase nouns for values (`ringTemplate`). Module constants: UPPER_SNAKE (`ASSETS`,
  `RING_SEGMENTS`); keys inside `ASSETS` are PascalCase.
- **Defaults keys:** PascalCase, noun first: `RingSize`, `RingTime`, `SparkCount`,
  `SparkSpeed`, `RockColor`. Suffixes: `Count` (integer), `Time` (effect seconds), `Speed`
  (studs/s; `SpinSpeed`/`RotSpeed` are degrees/s, matching the engine and MeshParticles),
  `Size` (studs), `Color` (Color3). Always include `Color` and `Scale`.
- **Defaults types:** number, boolean, string, Color3, Vector3 only. The harness turns
  Defaults into attributes and `P` prints only these back as Luau. Build NumberRange /
  NumberSequence / ColorSequence / Enum values inside `Play` from scalars
  (`NumberRange.new(p.SparkSpeed * 0.6, p.SparkSpeed)`).
- **Mesh templates:** PascalCase shape names (`CrescentThin170`), per `references/meshes.md`.
- **Instances in ctx.Folder:** optional PascalCase names (`Flash`, `Ring`) for debugging.

## Assets

The art library `ReplicatedStorage.Assets.VFX` is Studio-only (four folders of ImageButton
cards; table and lookup snippet in `references/textures.md`, "Asset library").

**Convention: copy ids into the effect.** Put every library id in the `ASSETS` table at the
top of the effect, with `-- <Folder>/<CardName>` so it can be found again. The library is
not on disk or Rojo-managed, and its cards are UI objects that can be renamed or moved; an
asset id never changes, and the effect file stays self-contained and reviewable.

Never `WaitForChild` into `Assets` from an effect. For quick prototyping only, a card can be
read at runtime with an id fallback:

```luau
local function cardImage(folderName, cardName) -- returns nil if anything is missing
	local node = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	for _, name in { "VFX", folderName, cardName, "Texture" } do
		node = node and node:FindFirstChild(name)
	end
	return node and node.Image
end

local glow = cardImage("StaticVFXTextures", "<CardName>") or ASSETS.CoreGlow
```

Replace it with the plain `ASSETS` id before the effect is done.

**Flipbooks:** grid = sheet / `OriginalRectSize` (1024 sheet: 512 -> `Grid2x2`,
256 -> `Grid4x4`, 128 -> `Grid8x8`). Note the grid in the `ASSETS` comment.

**Library meshes** (`MigratedMeshes`): rebuild as Part + `SpecialMesh` (FileMesh) from the
ids. A FileMesh is sized by `SpecialMesh.Scale`, not `Part.Size`: tween `mesh.Scale`, and
note that `MeshParticles.Burst` size curves do nothing on these parts (it sets `Part.Size`;
Transparency still works). For shrinking debris, use MeshFactory MeshPart templates.

**MeshFactory templates** live in `ReplicatedStorage.Assets.Meshes` (Studio-only). Look them up
without yielding and keep a plain-Part fallback (pattern in `examples/GroundSlam.luau`):

```luau
local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")
```

## Layering and timing (summary; details in the skill docs)

- 3-5 layers: core flash, primary shape, secondary particles, residue.
  Category breakdowns: `references/recipes.md`.
- Fast in (peak at 0.03-0.1s), slow out (fade 3-6x longer). Expansion easing: `Quad` or
  `Exponential` Out (`Enum.EasingStyle.Expo` does not exist).
- Typical durations: slash 0.2-0.4s, impact 0.3-0.6s, movement 0.3-0.5s, ground slam
  0.6-1.2s, buff 0.6-1.2s, explosion 0.8-1.5s.
- Sequence layers with `ctx.Wait`. For a parallel timeline use
  `task.spawn(function() ctx.Wait(t) ... end)`, never `task.delay` (real time). `Play`
  should return around the last layer's peak; `Linger` covers whatever is still fading.
- Energy: `LightEmission = 1`, `LightInfluence = 0`, Neon. Matter: `LightEmission = 0`.
- Budget, colors, and look: `SKILL.md` "Budget" and `references/style-guide.md` (still unfilled).

## Engine gotchas (verified in Studio)

- `ParticleEmitter.Size` is a **half-width**: `Size = 5` draws a 10x10-stud quad.
- Moving an `Attachment` (or an emitter's part) between `ctx.Emit` calls in the same frame
  does **not** move the spawn point; every burst lands where it was. To burst clusters at
  different spots from one emitter, give each cluster its own loop step (one burst per
  `ctx.Wait`). To scatter particles, emit
  from an invisible part (`ctx.Anchor()` resized) with `Shape = Disc` (radius = half the
  part's X/Z size; `ShapePartial` < 1 turns it into a ring), or use separate attachments.
- Flat ground/swirl layers: `Orientation = VelocityPerpendicular`,
  `EmissionDirection = Top`, `Speed` ~0.01 → the particle lies in the attachment's XZ
  plane; tilt the attachment to tilt it, spin it with `RotSpeed`.
- Slash flipbooks with dark pixels (e.g. "Medium Glowing Dark Slash") need
  `LightEmission` 0 or 1; values in between render the dark pixels black.
- Additive (`LightEmission = 1`) bright green with `Brightness` > 1 clips to mint/white on
  light ground. Keep `Brightness` ~1 and put a dark normal-blend layer behind it.
- Camera-facing particles near the ground get cut by it (hard straight edge). Raise them
  or shrink them; for flames, spawn ~0.5x their half-size above the ground. Used on purpose, a camera-facing disc centred on the ground reads as a
  dome (see `MagnetPull`).
- `Shape = Sphere` with `ShapePartial = 0.5` emits from the upper hemisphere only; with
  `ShapeStyle = Surface` and `ShapeInOut = Inward` particles fly to the centre (suction).
  Lifetime ≈ radius / Speed, slightly less so they vanish before overshooting.
- Streaks flowing inward **across the floor**: put a `Sphere`-shaped emitter on a flattened
  part (e.g. `2R x 0.2 x 2R`) with `ShapeStyle = Surface`, `ShapeInOut = Inward` and
  `VelocityParallel`; particles spawn on the ellipse rim and move radially to the centre.
  A `Disc` with `Inward` does not do this (nothing visible on the floor), and a
  `Cylinder` shape's axis is the part's **X**, so its "inward" streaks all run parallel.
- Ring textures put their ring well inside the quad (e.g. `thick ring 2` centre line at
  ~0.78 of the half-width, `thick ring 3` at ~0.75). Size = wanted ring radius / that
  fraction, or the ring lands inside the shape it should frame.
- `MigratedBeams` textures tile vertically, so as particles they show flat cut-off ends.
- A dark-coloured `Neon` part renders flat and unlit: good for translucent dark debris
  that shouldn't turn grey on its sunlit faces.
- A new texture can be blank for the first frames it is used (still loading). For
  screenshots, `ContentProvider:PreloadAsync` it or re-run the scrub.
- Beams and Trails draw their texture with the image's **top at Attachment0** and bottom at
  Attachment1 (TextureMode Stretch). Pick the attachment order to put the right end of a
  shape (e.g. the fanned-out end of grass strands) where you want it.
- `ParticleEmitter.Rotation`: positive values turn the texture counter-clockwise on screen.
- Moving a library effect's emitter through an orbit: set the attachment's CFrame, emit,
  then `ctx.Wait(1/60)` before moving again (see the shed streaks in `WindSpinSlash`).
- Library meshes are `SpecialMesh` FileMeshes: size with `SpecialMesh.Scale` (in native
  mesh units; get native size once via `AssetService:CreateMeshPartAsync(id).MeshSize`).
- `MeshPart.TextureID` ignores `Part.Color` (the texture's RGB shows as-is), and its alpha
  only cuts out holes once the part's `Transparency` is > 0 (0.02 is enough); at 0 the
  transparent pixels show the texture's RGB. So bake shell colours into the texture, keep
  a separate Neon body inside for an animated colour, and swap `TextureID` for stages
  (ash/dissolve frames).
- Neon renders colours lighter and yellower: `(255, 145, 35)` reads lemon. Push orange to
  roughly `(255, 110, 25)`. Dark Neon colours read much brighter than their RGB.
- `ForceField` material ignores `TextureID` and gives only a hairline rim (it also hides
  what's inside at `Transparency` 0). For a fresnel rim on a ball, use a camera-facing
  `thick ring 2` particle sized ~1.3x the radius with `ZOffset` = radius, so it draws at
  the front surface.
- Changing an emitter's `Color` / `Size` / `Transparency` applies to particles already
  alive, so one long-lived particle can be animated per frame. `LockedToPart` particles
  follow their attachment when it moves.
- `Trail.Lifetime` is real time, so trails are wrong in slow-mo and fade during a VFXScrub
  freeze. For projectile trails, use a Beam from the launch point to the head, bent into
  the flight parabola: `CurveSize0 = |v0| * t / 3`, `CurveSize1 = -|v(t)| * t / 3`, with
  both attachments' X axis along their velocity (verified).
- `Glass` on a dark part renders nearly invisible (it refracts the background). Use
  SmoothPlastic or Neon for dark solid shapes.
- Particles emitted inside an opaque mesh are hidden by it: spawn them above or in front.
- `ParticleEmitter.Squash`: positive values make the particle taller and narrower, and
  negative values make it wider. With `VelocityParallel`, use positive values for streaks
  along the flight.
- A Beam with `FaceCamera = false` spreads its width along its attachments' **Y axis**
  (verified on `LavaEruption`). Rotating the attachments so Y pointed at the viewer
  showed the sheet edge-on. For an upright sheet along a direction D, set the
  attachments to `CFrame.fromMatrix(pos, up, D)`. `Attachment.Position` is in the
  **parent part's** space, not the attachment's own rotated axes, so sway or offset
  rotated attachments in part axes.
- Before you change an emitter or beam property, grep the module for every place that
  writes it. Per-frame loops often reset `Lifetime`, `Speed`, `Size` or `Rotation` each
  frame, which silently undoes a change made only where the emitter is created
  (`LavaEruption` reset tongue `Lifetime` this way, so a "faster but same height"
  change made the wall taller).
- How high a rising particle gets ≈ `Speed × Lifetime` (less with `Drag`: `v/k ·
  (1 − e^(−k·t))`). Changing one without the other changes the height.
- Layout frames: `CFrame.lookAt(p, p + towardViewer)` has its RightVector pointing to the
  viewer's left. Build the frame facing away from the viewer
  (`CFrame.lookAt(p, p - towardViewer)`) so that +X = the viewer's right.
- Many flame flipbooks start with tiny frames: as a OneShot burst they stay invisible for
  most of a short lifetime. Use `FlipbookMode = Loop` + `FlipbookStartRandom = true` (and a
  framerate ~16-24) so every particle shows a full-size frame at once.
- A Top-face SurfaceGui runs the image's X along the part's **Z** axis. For a horizontal
  texture (a crack), make the part long on Z and turn it 90 deg about Y so its Z runs
  along the line you want.
- Ground-flat particles (`VelocityPerpendicular`): `Squash = -0.8` at `Rotation = 0`
  stretches the quad ~1.35x along the attachment's X and flattens it to ~0.3-0.4 across,
  giving an ellipse along X. `RotSpeed` turns the whole ellipse, so keep it small. Tilt the
  attachment to tilt the ellipse.
- `VelocityParallel` streaks with any spread toward or away from the camera smear sideways
  into long horizontal blades. For flames that lean, use `FacingCameraWorldUp` and lean
  them with `Rotation` (one emitter per side).
- A circular band (Tube mesh) can't follow a lumpy surface. Paint the band into the
  mesh's own texture instead, or draw the band as a camera-facing arc particle in front
  (`BandArc` on the gas dome).

### Learned by Roqer (verified in Studio there, not yet here)

From https://github.com/S4US/Roqer (AGPL-3.0-or-later). Details in the files named; move a
line up into the list above once it is checked in this project.
- `VelocityPerpendicular` at `Speed` 0 doesn't show at all; give it a tiny Speed (`design.md` 5).
- `VelocityParallel`: `Rotation` -90 puts the image's top first along the motion, 90 its
  bottom, 0 lays it across the motion; it follows the particle's own velocity (`design.md` 5).
- Transparency keys above 1 end a particle before its lifetime; negative Transparency doesn't
  make a soft texture solid (`design.md` 7).
- Black at `LightEmission` 0 is ink, at 0.55 a faint veil, at 1 invisible (`design.md` 3).
- Twins of a lopsided sprite line up only with one fixed `Rotation` and a shared `RotSpeed`
  (`design.md` 3).
- A Decal's `Color3` above 1 is overbright and blooms (`design.md` 4).
- `FlipbookIncompatible` says "must be 1024 by 1024" even for a 1024 sheet that plays
  (`drawing-textures.md`).
- An untextured Trail reads as a flat tube; a Trail's image top is at its head and its left
  edge at `Attachment0` (`motion.md`).
- `RenderFidelity = Automatic` turns a thin crescent into a wedge at distance (`meshes.md`).
- A camera shake applied as `camera.CFrame *= offset` each frame accumulates; undo it before
  the camera scripts run (`camera-world.md`).
- Newer avatars' shoulders are `AnimationConstraint`s, which `Motor6D` code skips silently
  (`camera-world.md`).

## Rules

1. Parent only under `ctx.Folder` (directly or via `ctx.Anchor()`). Forge layers are the one
   exception: ForgeVFX parks some of its parts in `workspace.Terrain` and removes them itself.
2. All timing through ctx: no `task.wait`, `wait`, `task.delay`, raw `TweenService`, or `emitter:Emit`.
   Forge layers go through `ctx.Forge`, never `ForgeVFX.emit` directly (it would ignore slow-mo).
3. `Rate = 0` on burst emitters.
4. Visible parts: `Anchored`; `CanCollide`, `CanQuery`, `CanTouch`, `CastShadow` false.
5. `Linger` covers the longest particle or mesh-particle lifetime after `Play` returns.
6. Effects may require `MeshParticles`; never `MeshFactory`, `VFXScrub` (edit-time tools),
   `ForgeBridge` or the ForgeVFX package (use `ctx.Forge`).
7. No hard runtime dependency on Studio-only folders: library assets as `ASSETS` ids,
   mesh templates with a plain-Part fallback, no `WaitForChild` into them.
8. Defaults: PascalCase keys, attribute-safe types, everything tunable exposed.
9. Stay inside the budget in `SKILL.md`.
10. Edit code on disk, never in Studio. Don't put Studio-made instances in Rojo folders.
11. Effects run on the client only.

## Testing (VFXHarness)

1. With `rojo serve` connected, press Play in Studio. The harness adds a button for every
   ModuleScript in `Effects` and a target part 12 studs in front of you.
2. Keys: `R` replay, `L` loop (every 1.5s, scaled), `[` / `]` speed 0.1 / 0.25 / 0.5 / 1x,
   `T` move target in front of you, `P` print current params as a `Effect.Defaults` table.
   Each key also has an on-screen button (Replay, Loop, Target, Slower, Faster, Print), so
   the harness works on touch: use Studio's device emulator, or join the published place on
   a phone (the harness runs outside Studio too; `P` output goes to the Developer Console).
   `Hide` collapses the panel so it doesn't cover the effect.
3. Tune live: select `Workspace.VFXHarnessConfig.<Effect>` and edit its attributes. Press `P`
   and paste into the file on disk before stopping; edits are lost on stop.
4. Effects are required once per session. After editing a file (or adding a new effect),
   stop and press Play again.
5. Check at 1x for feel, at 0.1x for layer order and pops, and from ~40 studs for
   readability. Output must show no `VFXPlayer: effect ... errored` or `VFXHarness` warnings.
6. Judge the captures with the questions in `references/review.md` (two views: close, and
   from the player's camera), and run the colour check on them:
   `node tools/vfx/clip.mjs tone --dir <captures> --empty <capture past the end>`.

### Frame-by-frame screenshots (VFXScrub, Edit mode)

To match a reference video, compare the same effect times side by side:

```luau
local Scrub = require(game.ReplicatedStorage.Shared.VFX.VFXScrub)
local t, count = Scrub.Play("WindSpinSlash", dummy.HumanoidRootPart.CFrame, nil, 0.1)
-- screenshot now (Studio MCP screen_capture with a fixed camera), then Scrub.Clear()
```

`Play` requires a fresh copy of the effect (picks up edits), seeds `math.random`, advances
at 0.1x and freezes particles, tweens and MeshParticles within one frame of `stopAt`. Use a fixed
camera position/FOV for every capture and an R15 dummy for scale. Extract reference frames
with ffmpeg at the same times (t = 0 at the slash's first frame).

### Matching a reference video (workflow)

`tools/vfx/clip.mjs` does the frame work (needs Node and ffmpeg on PATH; `node
tools/vfx/clip.mjs help`). Every time it prints or labels is effect seconds (real game time).

1. Read the clip: `node tools/vfx/clip.mjs read <video> --from <s> --to <s> [--speed 0.25]`
   (`--speed` for a slowed recording; default output `.vfx-clips/<name>/`). It stores up to
   300 frames, prints measurements and writes `overview.png` (16 frames over where the clip
   changes) and, when the overview steps over the start, `closeup.png`. The measurements:
   - **Timing:** "starts" is when the first layer emits; "peaks" when the flash or core is
     brightest; "falls to half by" places the main layer's fade; "gone by" is the latest any
     layer may still show (its delay plus its lifetime).
   - **Brightness:** a peak near white across the frame is a flash core (short life,
     `LightEmission` 1, high Brightness); a small rise is a glow.
   - **Size:** the share of the frame, and how much it grows from start to largest, is a ratio
     for a `Size` sequence, not studs: the clip's camera is not Studio's.
   - **Colours by phase:** `ColorSequence` keypoints in order (build-up, peak, fade). Fading
     pixels are mixed with the background, so take the hue and lift its brightness rather than
     copying a muddy value.
   - **A moving camera** is reported as such; read the timing from the frame labels instead.
   Compression, bloom and the background shift every number: check each against the frames.
   Before building, name the layers the frames show in the order they appear (anticipation,
   flash or core, main body, secondaries, smoke and fade), each with the times its labels show.
   Then look closer at fast stretches one at a time:
   `node tools/vfx/clip.mjs span <clip dir> --from 0 --to 0.2 --count 16` (`--crop full` to see
   the ground or the caster around the effect).
   A 0.25x slow-motion recording is far easier to read than 1x; measure real timing from the
   1x one.
   **Highly detailed or fast effects (explosions, slashes, flashes, impacts, anything whose
   onset is under ~0.5 s) are analysed every 10 ms of real time**, start to finish. A 1x
   60 fps video only has a frame every ~16.7 ms, so use the slow-motion recording: `clip.mjs
   read --speed 0.25` on it stores every frame (at 60 fps, 4.2 ms of real time each; at most
   300 frames, so read the onset as its own short `--from/--to` stretch) and labels each with
   its real-time offset, and `span --count 16` over 0.15 s gives ~10 ms steps. Slower effects
   can use ~25-50 ms through the onset and ~100 ms through steady phases and the fade.
2. Build the effect, then capture the same moments with VFXScrub and a fixed camera at
   the reference's elevation, save them named by effect time (`0.10.png`) and put them side
   by side with `node tools/vfx/clip.mjs compare <clip dir> --captures <folder>` (clip R left,
   ours S right, labelled with effect times; at most 8 moments a sheet). Compare when each layer
   starts, peaks and fades, its size against the frame, its colours and its shape: proportions,
   not position.
   **The goal is that any timestamp looks almost the same as the reference**, not just a few
   key frames: capture ours at the same increments as the reference (10 ms for detailed or
   fast effects, see step 1; scrub at 0.05x for t < 0.3 s, since Studio Edit mode can stall
   ~0.3 s mid-effect and overshoot the freeze time at 0.1x), and when the reference comes from more
   than one camera angle, match a camera to each and compare every angle at the same times.
   A layer that looks right from the front can be flat, thin or misplaced from the side.
3. Grade each round with a grader subagent that compares **only against the reference**
   (state anything intentionally out of scope). Resume the same grader for later rounds so
   it remembers earlier scores. Apply its fixes, re-capture, repeat until it says the
   remaining gaps are noise (usually 3-4 rounds).
4. Finish with a read-only file-integrity subagent: contract, rules grep, Linger maths,
   budget counts, docs accuracy.
5. Before every capture, check the Studio module's Source hash matches the disk file (Rojo
   can be disconnected or two-way sync can revert edits). A new texture can render blank on
   first use: preload it or re-run the scrub.
6. Say what you approximated. Roblox has no custom shaders, so distortion, heat haze,
   refraction, an engine's bloom strength and textures you cannot see in the frames can only
   be approximated, and particle counts can't be read from frames. Say which parts are
   approximations; don't claim it matches. If the result looks clearly faster or slower than
   the clip and the clip's speed wasn't given, ask.
7. Write down what you learned: new textures in `references/textures.md`, verified engine
   behaviour in "Engine gotchas", a recipe for a new effect category in
   `references/recipes.md`.

## New effect checklist

- [ ] Classified, matching recipe read, closest file in `examples/` used as the base.
- [ ] `src/shared/VFX/Effects/<Name>.luau` created on disk; PascalCase name describes the look.
- [ ] Header comment: Studio path, one-line look, layer list.
- [ ] Every library id in `ASSETS` with a `-- <Folder>/<CardName>` comment (and flipbook grid).
- [ ] All tunables in `Defaults` (incl. `Color`, `Scale`), attribute-safe types only.
- [ ] `Linger` covers the longest lifetime.
- [ ] Mesh templates looked up without yielding, with a fallback; no `MeshFactory` require.
- [ ] Rules grep is clean:
      `grep -nE "task\.(wait|delay)|[^.]wait\(|TweenService|:Emit\(|MeshFactory|ForgeVFX|ForgeBridge|\.emit\(" src/shared/VFX/Effects/<Name>.luau`
- [ ] Forge layers only if the effect needs them (see "VFX Forge layers"); template looked up
      without yielding, with a warning if missing; `Linger` covers the Forge layers' end.
- [ ] Within budget.
- [ ] Tested in the harness at 1x and 0.1x; tuned Defaults pasted back.
- [ ] Captures judged with `references/review.md` from the close and the player's view; colour
      check run (`clip.mjs tone`).
- [ ] Drawn flipbooks pass `tools/vfx/flipbook.mjs` (no problems; notes weighed).
- [ ] Reusable new textures added to `references/textures.md`.

## Open issues (2026-10-12; delete each line when fixed)

- `ctx` has no camera/screen helper (FOV, blur, impact frames, shake), so effects can't use
  `references/camera-world.md` without breaking rule 1. Add one to `VFXPlayer` (and mirror it
  in `VFXScrub`) when the first effect needs it.
- `tools/vfx` (2026-10-21) was tested on synthetic clips and sheets in a Linux container, not
  yet on Oscar's Windows PC; `vfxtex.render_flipbook` and MeshFactory `Surface`/`Swirl`/`Dome`
  have not run in Blender/Studio yet.

- `references/style-guide.md` is an unfilled template.
- `core.autocrlf=true` rewrites files to CRLF on checkout; consider a `.gitattributes`
  with `* text=auto eol=lf` so Luau files stay LF.
