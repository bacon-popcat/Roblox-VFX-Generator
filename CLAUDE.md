# Roblox VFX

Roblox visual effects as Luau ModuleScripts, synced into Roblox Studio with Rojo.

- Project folder: `C:\Users\oscar\Documents\Rojo Roblox\VFX`. Work only here; there is no
  OneDrive copy any more.
- Structure, naming, asset and testing conventions: `VFX_STRUCTURE.md`.
- Writing effects: use the `roblox-vfx` skill (`.claude/skills/roblox-vfx/`).

## Working with Studio

- Edit files on disk; `rojo serve` (started from VS Code, port 34872) syncs `src/` into
  Studio. Never edit synced scripts inside Studio.
- After `rojo serve` restarts, the Rojo plugin in Studio has to reconnect before changes
  arrive. Before testing, check that the script in Studio matches the file on disk.
- The art library (`ReplicatedStorage.Assets.VFX`) and mesh templates
  (`ReplicatedStorage.VFX.Meshes`) live only in Studio. Reference library assets by id.
- Preview effects frame by frame in Edit mode with `ReplicatedStorage.Shared.VFX.VFXScrub`
  and the Studio MCP screenshot tool; try them at full speed in the VFXHarness (Play mode).

## When to commit
- Create commits after completing each logical unit of work.
- Do not push to the remote repository unless asked.
- Use conventional commit messages (e.g. "feat:", "fix:", "refactor:").
