# Textures

Prefer these. Add new rows as textures are uploaded (name | id | use).

| Name | Id | Use |
|---|---|---|
| sparkles | rbxasset://textures/particles/sparkles_main.dds | Sparks, glints |
| smoke | rbxasset://textures/particles/smoke_main.dds | Smoke, dust |
| fire | rbxasset://textures/particles/fire_main.dds | Flames |
| Medium Glowing Dark Slash | rbxassetid://107491452097107 | 4x4 flipbook, multi-strand slash sweep; additive (LightEmission 1) |
| Wide Dark Slash | rbxassetid://104673447334638 | 4x4 flipbook, dark wide crescent; normal blend under additive slashes |
| Glowing Slash | rbxassetid://13580352351 | 4x4 flipbook, crisp bright crescent (hot highlight) |
| Crescent32 | rbxassetid://17388445727 | Static layered crescent strokes (flat vortex layers) |
| Crescent18 | rbxassetid://17388365742 | Static thin clean crescent (trailing lines) |
| Smokey Shockwave | rbxassetid://12318427672 | Grey wind ring lying on the ground |
| Swirls21 | rbxassetid://130391463304711 | Thin swirl lines (ground wind detail) |
| Star102 | rbxassetid://17391818367 | Long 4-point glare for flashes |
| Blurred Spec 11 | rbxassetid://284205403 | Round soft glow |
| Star153 | rbxassetid://16444981264 | Small 4-point sparkle |
| smoke 41 | rbxassetid://111394301752764 | Soft smoke puff |
| Leaf (mesh) | rbxassetid://5129539702 | MigratedMeshes leaf, native 5.45 x 1.61 x 11.0 (SpecialMesh) |
| Thin Basic Slash | rbxassetid://85263893313331 | 4x4 flipbook, thin clean arc; tinted near-black for ink strokes in a slash |
| Shaded Slash 5 | rbxassetid://118897571793559 | 4x4 flipbook, streaky arc with dark fibres |
| grass1Other | rbxassetid://91858314987113 | Three curved grass blades; as a Beam texture = wind strands on a sword |
| Sideways Spec 41 | rbxassetid://10614304526 | Thin needle; long flash rays, streak particles, blade glow |
| Sideways Spec 50 | rbxassetid://6893847210 | Tapered spike; tinted black = tiny ink streaks shed off a slash |
| BeamSoftBlurredStreaks | rbxassetid://13280046773 | Soft streaky Trail texture for weapon motion trails |

Gradient strips used as mesh `TextureID` should fade left to right (along U),
matching the MeshFactory UV layout.

<!-- Add your own uploaded textures below, e.g.
| soft_glow | rbxassetid://000000 | Round soft glow for cores and auras |
| slash_gradient | rbxassetid://000000 | Horizontal fade for Crescent meshes |
-->

## Asset library

The game's art library lives in Studio only, at `ReplicatedStorage/Assets/VFX`. It is
not on disk and not managed by Rojo. Each entry is an ImageButton "card" named after
the asset.

| Folder | Count | Where the id is | Use |
|---|---|---|---|
| `StaticVFXTextures` | 4207 | `card.Texture.Image` (ImageLabel child) | Particle, mesh and glow textures |
| `FlipbookTextures` | 2711 | `card.Texture.Image`; cell size in `card.Texture:GetAttribute("OriginalRectSize")` | Animated particle sheets |
| `MigratedBeams` | 450 | `card.Texture.Image` | Beam and Trail textures |
| `MigratedMeshes` | 158 | `SpecialMesh` under `card.ViewportFrame.MeshWorld.<Name>.MeshPart` (MeshId, TextureId, Scale) | Ready-made mesh shapes |

- **Copy ids, don't read cards at runtime.** Find a card in Studio, then hard-code its
  id in the effect's `ASSETS` table with a `-- <Folder>/<CardName>` comment (see
  `VFX_STRUCTURE.md`, "Assets").
- **Flipbooks:** grid = sheet size / cell size. On a 1024 sheet: 512 -> `Grid2x2`,
  256 -> `Grid4x4`, 128 -> `Grid8x8`. Use `FlipbookMode = OneShot` for bursts (plays
  once over each particle's lifetime).
- **Library meshes** are `SpecialMesh` (FileMesh) data, so rebuild them as a Part +
  SpecialMesh. A FileMesh is sized by `SpecialMesh.Scale`, not `Part.Size`.

Find cards by keyword (Edit mode, command bar or execute_luau):

```luau
local lib = game.ReplicatedStorage.Assets.VFX
local keyword = "slash"
for _, folder in lib:GetChildren() do
	for _, card in folder:GetChildren() do
		if card.Name:lower():find(keyword, 1, true) then
			local tex = card:FindFirstChild("Texture")
			local mesh = card:FindFirstChildWhichIsA("SpecialMesh", true)
			print(folder.Name .. "/" .. card.Name,
				tex and tex.Image or (mesh and mesh.MeshId),
				tex and tex:GetAttribute("OriginalRectSize") or (mesh and mesh.Scale))
		end
	end
end
```

Add a row to the table at the top for any library texture you reuse often.
