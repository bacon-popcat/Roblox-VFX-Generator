# VFX code structure

The authoritative guide to where VFX code lives and how it is organized. How to *design*
an effect (layers, values, recipes) lives in the skill docs:
`.claude/skills/roblox-vfx/SKILL.md` and its `references/`. Read both before writing an effect.

## Layout

Disk is the source of truth for code. `rojo serve` syncs `src/` into Studio live; edits
made to synced scripts inside Studio are overwritten. Edit files on disk only. If the
Rojo plugin in Studio is not connected, nothing syncs: connect it (or push the changed
module's `Source` yourself and checksum it) before testing.

```
VFX/                                  (repo root)
├── default.project.json              Rojo tree (below)
├── VFX_STRUCTURE.md                  this file
├── .claude/skills/roblox-vfx/        skill: SKILL.md, references/*.md, examples/*.luau
└── src/
    ├── shared/VFX/
    │   ├── VFXPlayer.luau            plays effects by name, builds ctx
    │   ├── MeshParticles.luau        MeshPart "particles" (client sim)
    │   ├── MeshFactory.luau          edit-time mesh generator/publisher
    │   ├── VFXScrub.luau             edit-time freeze-frame player for screenshots
    │   └── Effects/<Name>.luau       one ModuleScript per effect
    ├── client/init.client.luau       VFXHarness test bench (Studio only)
    └── server/init.server.luau       placeholder (VFX is client-only)
```

| Disk | Studio | Class |
|---|---|---|
| `src/shared/VFX/VFXPlayer.luau` | `ReplicatedStorage.Shared.VFX.VFXPlayer` | ModuleScript |
| `src/shared/VFX/MeshParticles.luau` | `ReplicatedStorage.Shared.VFX.MeshParticles` | ModuleScript |
| `src/shared/VFX/MeshFactory.luau` | `ReplicatedStorage.Shared.VFX.MeshFactory` | ModuleScript |
| `src/shared/VFX/VFXScrub.luau` | `ReplicatedStorage.Shared.VFX.VFXScrub` | ModuleScript |
| `src/shared/VFX/Effects/<Name>.luau` | `ReplicatedStorage.Shared.VFX.Effects.<Name>` | ModuleScript |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` | LocalScript |
| `src/server/init.server.luau` | `ServerScriptService.Server` | Script |
| (not on disk) | `ReplicatedStorage.VFX.Meshes` | Folder of MeshFactory templates |
| (not on disk) | `ReplicatedStorage.Assets.VFX` | Art library (asset cards) |
| (runtime) | `Workspace.ActiveVFX.<Name>` | `ctx.Folder`, one per play |
| (edit time) | `Workspace.VFXScrub` | `ctx.Folder` of a VFXScrub freeze-frame; `Clear()` removes it |
| (runtime, harness) | `Workspace.VFXHarnessConfig`, `Workspace.VFXTarget`, `PlayerGui.VFXHarness` | |

Rojo rules that matter here:
- File name = instance name. `.luau` = ModuleScript, `.client.luau` = LocalScript,
  `.server.luau` = Script. `init.*.luau` turns its folder into that script, so any other
  file in `src/client/` becomes a child ModuleScript of the `Client` LocalScript.
- Folders mapped with `$path` are Rojo-owned: Rojo can delete instances that aren't on
  disk. Never store Studio-made content (mesh templates, assets) under `Shared`,
  `Client`, or `Server`. Studio-only content goes in `ReplicatedStorage.VFX.Meshes` or
  `ReplicatedStorage.Assets`.
- Don't confuse `ReplicatedStorage.Shared.VFX` (code, Rojo) with `ReplicatedStorage.VFX`
  (Studio-only mesh templates).

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
only. Server-triggered effects need a RemoteEvent (none exists yet).

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
| `ctx.Wait(t)` | | Yield in effect time. |

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

**MeshFactory templates** live in `ReplicatedStorage.VFX.Meshes` (Studio-only). Look them up
without yielding and keep a plain-Part fallback (pattern in `examples/GroundSlam.luau`):

```luau
local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("VFX") -- not Shared.VFX
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
- Moving an `Attachment` between `ctx.Emit` calls in the same frame does **not** move the
  spawn point; every burst lands where the attachment was. To scatter particles, emit
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
  or shrink them.
- Beams and Trails draw their texture with the image's **top at Attachment0** and bottom at
  Attachment1 (TextureMode Stretch). Pick the attachment order to put the right end of a
  shape (e.g. the fanned-out end of grass strands) where you want it.
- `ParticleEmitter.Rotation`: positive values turn the texture counter-clockwise on screen.
- Moving a library effect's emitter through an orbit: set the attachment's CFrame, emit,
  then `ctx.Wait(1/60)` before moving again (see the shed streaks in `WindSpinSlash`).
- Library meshes are `SpecialMesh` FileMeshes: size with `SpecialMesh.Scale` (in native
  mesh units; get native size once via `AssetService:CreateMeshPartAsync(id).MeshSize`).

## Rules

1. Parent only under `ctx.Folder` (directly or via `ctx.Anchor()`).
2. All timing through ctx: no `task.wait`, `wait`, `task.delay`, raw `TweenService`, or `emitter:Emit`.
3. `Rate = 0` on burst emitters.
4. Visible parts: `Anchored`; `CanCollide`, `CanQuery`, `CanTouch`, `CastShadow` false.
5. `Linger` covers the longest particle or mesh-particle lifetime after `Play` returns.
6. Effects may require `MeshParticles`; never `MeshFactory` or `VFXScrub` (edit-time tools).
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
3. Tune live: select `Workspace.VFXHarnessConfig.<Effect>` and edit its attributes. Press `P`
   and paste into the file on disk before stopping; edits are lost on stop.
4. Effects are required once per session. After editing a file (or adding a new effect),
   stop and press Play again.
5. Check at 1x for feel, at 0.1x for layer order and pops, and from ~40 studs for
   readability. Output must show no `VFXPlayer: effect ... errored` or `VFXHarness` warnings.

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

## New effect checklist

- [ ] Classified, matching recipe read, closest file in `examples/` used as the base.
- [ ] `src/shared/VFX/Effects/<Name>.luau` created on disk; PascalCase name describes the look.
- [ ] Header comment: Studio path, one-line look, layer list.
- [ ] Every library id in `ASSETS` with a `-- <Folder>/<CardName>` comment (and flipbook grid).
- [ ] All tunables in `Defaults` (incl. `Color`, `Scale`), attribute-safe types only.
- [ ] `Linger` covers the longest lifetime.
- [ ] Mesh templates looked up without yielding, with a fallback; no `MeshFactory` require.
- [ ] Rules grep is clean:
      `grep -nE "task\.(wait|delay)|[^.]wait\(|TweenService|:Emit\(|MeshFactory" src/shared/VFX/Effects/<Name>.luau`
- [ ] Within budget.
- [ ] Tested in the harness at 1x and 0.1x; tuned Defaults pasted back.
- [ ] Reusable new textures added to `references/textures.md`.

## Open issues (2026-10-12; delete each line when fixed)

- The project lives at `C:\Users\oscar\Documents\Rojo Roblox\VFX`. An older copy in
  OneDrive caused "Rojo isn't syncing" on 2026-10-12 (edits went to the copy VS Code wasn't
  serving). Work only in the Documents folder. After restarting `rojo serve`, reconnect the
  Rojo plugin in Studio.

- `references/style-guide.md` is an unfilled template.
- `core.autocrlf=true` rewrites files to CRLF on checkout; consider a `.gitattributes`
  with `* text=auto eol=lf` so Luau files stay LF.
- The effect instance budget in `SKILL.md` (~10) is tight for layered hero effects:
  `WindSpinSlash` creates ~25 (mostly ParticleEmitters/Attachments, all destroyed after
  ~2s). Decide whether emitters count toward it.
