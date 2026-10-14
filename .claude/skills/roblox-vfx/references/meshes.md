# Making meshes

Mesh assets for effects are generated with code, never sculpted.
Tool: `ReplicatedStorage/Shared/VFX/MeshFactory`. Run it in Edit mode only (via
execute_luau). Effects must never require it.

```luau
local MF = require(game.ReplicatedStorage.Shared.VFX.MeshFactory)
```

## Workflow

1. **Reuse first.** Look in `ReplicatedStorage/VFX/Meshes` (a Studio-only folder that
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
   if one exists, otherwise uploads and saves a template to `ReplicatedStorage/VFX/Meshes/<name>`.
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
  yet":** confirmed for execute_luau (2026-10-13). Building and previewing still work.
  To get a real mesh asset, export geometry as FBX to `assets/meshes/` and ask the user
  to import it with Studio's 3D Importer, then record the MeshId.
- **Wrong owner:** if the game is group-owned, pass
  `{ Id = groupId, Type = Enum.AssetCreatorType.Group }` as the creator so the mesh
  loads in that game.
- **New mesh shows blank or fails to load:** it may still be in moderation. Use the
  fallback and check again later.

## Not for this tool

Detailed organic or prop models (a sword, a creature, a tree), or shapes that are much
easier to model than to write as a generator. Model those in Blender
(`mcp__Blender__execute_blender_code`, in a separate scene so the user's scene is
untouched). Then either export triangles + UVs (convert Blender Z-up to Roblox Y-up as
`(x, z, -y)`) and feed them to `MeshFactory.Build` for previews, or export FBX for the
3D Importer. The Studio MCP's generate_mesh is the quick AI alternative.
