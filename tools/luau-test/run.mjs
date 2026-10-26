#!/usr/bin/env node
// Runs the VFX effect modules outside Studio: bundles tools/luau-test/runtime.luau (Roblox
// stubs that type-check every property), the modules in src/shared/VFX and a driver into one
// Luau chunk and runs it with the `luau` CLI (https://github.com/luau-lang/luau/releases;
// put it on PATH or set LUAU=/path/to/luau).
//
//   node tools/luau-test/run.mjs                 every effect, at 1x and 0.25x
//   node tools/luau-test/run.mjs LavaEruption    one effect
//   node tools/luau-test/run.mjs --examples      also the roblox-vfx skill's examples/
//
// It catches errors, bad property names/types/enums, malformed sequences, Linger that cuts
// particles off, and instances left outside ctx.Folder. It does not render: look at the
// effect in Studio as well.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const vfx = path.join(root, "src", "shared", "VFX");

// Extra cases with overrides: [name, Luau table source, label]
const CASES = {
  WindBladeTrail: [["WindBladeTrail", "{ Weapon = (function() local p = Instance.new('Part'); p.Name = 'TestWeapon'; p.Size = Vector3.new(0.2, 4, 0.3); p.Parent = workspace; return p end)() }", "with Weapon"]],
  WindSpinSlashCombo: [["WindSpinSlashCombo", "{ WindupTime = 0.35 }", "Wind Sword timing"]],
  MagnetPull: [["MagnetPull", "{ BlackHole = false }", "BlackHole off"]],
};

const args = process.argv.slice(2);
const withExamples = args.includes("--examples");
const only = args.filter((a) => a !== "--examples");
const modules = [];
for (const file of fs.readdirSync(vfx).filter((f) => f.endsWith(".luau"))) {
  modules.push([`Shared.VFX.${path.basename(file, ".luau")}`, path.join(vfx, file)]);
}
const effectFiles = new Map();
for (const f of fs.readdirSync(path.join(vfx, "Effects")).filter((f) => f.endsWith(".luau"))) effectFiles.set(path.basename(f, ".luau"), path.join(vfx, "Effects", f));
// The skill's examples run as if they were in Effects/ (a real effect of the same name wins).
if (withExamples) {
  const examples = path.join(root, ".claude", "skills", "roblox-vfx", "examples");
  for (const f of fs.readdirSync(examples).filter((f) => f.endsWith(".luau"))) {
    const name = path.basename(f, ".luau");
    if (!effectFiles.has(name)) effectFiles.set(name, path.join(examples, f));
  }
}
const effectNames = [...effectFiles.keys()].sort();
for (const name of effectNames) modules.push([`Shared.VFX.Effects.${name}`, effectFiles.get(name)]);

const cases = [];
for (const name of effectNames) {
  if (only.length && !only.includes(name)) continue;
  cases.push(`{ "${name}", {} }`);
  for (const [n, overrides, label] of CASES[name] ?? []) cases.push(`{ "${n}", ${overrides}, "${label}" }`);
}

const strip = (source) => source.replace(/^--!.*$/gm, "");
// Each piece of the bundle and the line it starts on, to map errors back to source files.
const pieces = [];
let bundle = "";
const add = (text, file) => {
  const startLine = bundle.split("\n").length;
  bundle += text;
  if (file) pieces.push({ file: path.relative(root, file), startLine, lines: text.split("\n").length });
};
add("local Runtime = (function()\n");
add(strip(fs.readFileSync(path.join(here, "runtime.luau"), "utf8")), path.join(here, "runtime.luau"));
add("\nend)()\n");
for (const [studioPath, file] of modules) {
  add(`Runtime.addModule(${JSON.stringify(studioPath)}, function(script)\n`);
  add(strip(fs.readFileSync(file, "utf8")), file);
  add("\nend)\n");
}
add(`EFFECTS = {\n${cases.join(",\n")}\n}\n`);
add(fs.readFileSync(path.join(here, "driver.luau"), "utf8"), path.join(here, "driver.luau"));
const mapLine = (line) => {
  for (const piece of pieces) {
    if (line >= piece.startLine && line < piece.startLine + piece.lines) return `${piece.file}:${line - piece.startLine + 1}`;
  }
  return `bundle:${line}`;
};
const remap = (text) => text.replace(/[^\s:]*\.bundle\.luau:(\d+)/g, (_, line) => mapLine(Number(line)));

const out = path.join(here, ".bundle.luau");
fs.writeFileSync(out, bundle);
const luau = process.env.LUAU || "luau";
const result = spawnSync(luau, [out], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
if (result.error) {
  console.error(result.error.code === "ENOENT" ? `luau not found; install it or set LUAU (${luau})` : result.error.message);
  process.exit(2);
}
process.stdout.write(remap(result.stdout));
process.stderr.write(remap(result.stderr));
process.exit(result.status === 0 && result.stdout.includes("ALL OK") ? 0 : 1);
