# Making meshes

Mesh assets for effects are generated with code, never sculpted.
Tool: `ReplicatedStorage/Shared/VFX/MeshFactory`. Run it in Edit mode only (via
execute_luau). Effects must never require it.

```luau
local MF = require(game.ReplicatedStorage.Shared.VFX.MeshFactory)
```

## Workflow

1. **Reuse first.** Look in `ReplicatedStorage/Assets/Meshes` (a Studio-only folder that
   MeshFactory creates; it is not on disk and is separate from the code folder
   `ReplicatedStorage/Shared/VFX`). Each template has
   `Generator`, `Params`, and `AssetId` attributes. If a close match exists, use it
   and scale it in the effect instead of making a new mesh.
   `MF.FindExisting(generator, params)` checks for an exact match.
   The art library's `MigratedMeshes` folder also has ready-made meshes (see
   `textures.md`, "Asset library").
2. **Pick a generator** from the table below. Tune its params.
3. **Preview before publishing.**
   ```luau
   local mesh = MF.Generators.Crescent({ Radius = 4, Arc = 170 })
   local preview = MF.Preview(mesh) -- temporary MeshPart at (0, 6, 0), not saved
   ```
   Screenshot it from 2 angles with screen_capture. Check: right shape, no holes,
   no inside-out faces (looks dark or invisible from outside), sensible size.
   Destroy the preview after. Adjust params and repeat if needed.
4. **Publish** with `MF.Make(name, generator, params)`. It reuses an exact match
   if one exists, otherwise uploads and saves a template to `ReplicatedStorage/Assets/Meshes/<name>`.
   Names are PascalCase and describe the shape, not the effect:
   `CrescentThin170`, not `RangerSlash`.
5. **Use it** in the effect: clone `Meshes.<Name>` for a single animated mesh, or
   pass the template to `MeshParticles.Burst` for many pieces. Include a plain-Part
   fallback in case the template is missing (see `examples/GroundSlam.luau`).

## Generators

All shapes have Y up. U runs along the length or around the shape, V across it.

| Generator | Shape | Key params |
|---|---|---|
| Crescent | Flat tapered slash arc, centered on +X | Radius, Width, Arc (deg), Segments, Taper |
| Ring | Flat ring | InnerRadius, OuterRadius, Segments |
| Tube | Open (flared) cylinder wall | Radius, Height, Flare, Segments |
| Spike | Cone pointing up | Radius, Height, Sides |
| Shard | Jittered crystal double-pyramid | Length, Width, Sides, Seed |
| Rock | Lumpy noise sphere | Radius, Rings, Segments, Roughness, Squash (Vector3), Seed |
| Sphere | Smooth UV sphere, equirect UVs (U around Y, V = 0 at the top pole) | Radius, Rings, Segments |

For variety (debris), publish 2-3 seeds of the same generator rather than one.

## When no generator fits

Write a new generator in MeshFactory using `MeshFactory.Build(positions, uvs, tris, opts)`:
- `positions` and `uvs` are parallel arrays (one entry per vertex); `tris` are
  `{i, j, k}` index triples.
- Y up; flat shapes in the XZ plane.
- U along the length or around the shape, V across it (0 -> 1).
- Thin/open shapes: `doubleSided = true`. Closed convex shapes: `orientOutward = true`.
- Under ~1000 triangles (the budget in `SKILL.md`).
Add it to `MeshFactory.Generators` and to the table above once it works.

## Troubleshooting

- **Publish fails with "CreateAssetAsync and CreateAssetVersionAsync are not available
  yet":** the Studio beta feature for asset creation is off. Ask the user to enable it
  (and restart Studio). Fallback: export FBX to `assets/meshes/` for the 3D Importer.
- **Wrong owner:** if the game is group-owned, pass
  `{ Id = groupId, Type = Enum.AssetCreatorType.Group }` as the creator so the mesh
  loads in that game.
- **New mesh shows blank or fails to load:** it may still be in moderation. Use the
  fallback and check again later.

## Not for this tool

Detailed organic or prop models (a sword, a creature, a tree), or shapes that are much
easier to model than to write as a generator. Model those in Blender
(`mcp__Blender__execute_blender_code`, in a separate scene so the user's scene is
untouched). Export triangles + UVs as JSON (convert Blender Z-up to Roblox Y-up as
`(x, z, -y)`), then get the data into Studio without retyping it: write the JSON to
`src/shared/TempMeshData.json` (Rojo syncs it as a ModuleScript), check a checksum
(triangle count and index sum) against the file, `require` it, `MeshFactory.Build` +
`MeshFactory.Publish` (generator name "Blender"), then delete the temp file. Never paste
large mesh data into execute_luau by hand; it gets corrupted. Also save an FBX to
`assets/meshes/` as the source. The Studio MCP's generate_mesh is the quick AI alternative.

| Mesh | Id | Use |
|---|---|---|
| SpiralRibbon | rbxassetid://129291594721141 | Blender: 2-turn tapering spiral ribbon, ~5.6 x 6.7 x 4.9; vortex/tornado layer (`assets/meshes/SpiralRibbon.fbx`) |
| SmoothSphere | rbxassetid://132254310752039 | MeshFactory Sphere (Radius 0.5, 14 x 28, 728 tris): 1-stud textured ball (fireball balls, spot/lava/dissolve shells) |
| TubeBand | rbxassetid://91818310113323 | MeshFactory Tube (Radius 1, Height 0.2): short open band; currently unused |
| BlobDome | rbxassetid://108920859813727 | Blender metaballs: lumpy squashed dome, 2 x 0.76 x 1.9, 840 tris, spherical UVs; dark base under an explosion (`assets/meshes/BaseBlob.fbx`) |
| ShellShard1 / ShellShard2 | rbxassetid://88449942291976 / 87477348430076 | Blender: jagged curved fragments of a 0.07-thick sphere shell (~1.2 / 1.0 studs, 268 / 196 tris); crumbling-shell chips for MeshParticles (`assets/meshes/ShellShard.fbx`) |
