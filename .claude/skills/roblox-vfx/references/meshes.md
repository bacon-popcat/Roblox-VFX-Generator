# Making meshes

Mesh assets for effects are generated with code, never sculpted.
Tool: `ReplicatedStorage/VFX/MeshFactory`. Run it in Edit mode only (via
execute_luau). Effects must never require it.

```luau
local MF = require(game.ReplicatedStorage.VFX.MeshFactory)
```

## Workflow

1. **Reuse first.** Look in `ReplicatedStorage/VFX/Meshes`. Each template has
   `Generator`, `Params`, and `AssetId` attributes. If a close match exists, use it
   and scale it in the effect instead of making a new mesh.
   `MF.FindExisting(generator, params)` checks for an exact match.
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
   if one exists, otherwise uploads and saves a template to `VFX/Meshes/<name>`.
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
- Under ~500 triangles.
Add it to `MeshFactory.Generators` and to the table above once it works.

## Troubleshooting

- **Publish fails with a permissions error:** execute_luau may not be allowed to
  create assets. Tell the user; publishing may need to run from a Studio plugin.
- **Wrong owner:** if the game is group-owned, pass
  `{ Id = groupId, Type = Enum.AssetCreatorType.Group }` as the creator so the mesh
  loads in that game.
- **New mesh shows blank or fails to load:** it may still be in moderation. Use the
  fallback and check again later.

## Not for this tool

Detailed organic or prop models (a sword, a creature, a tree). For those, use
the Studio MCP's generate_mesh, or ask the user for a model.
