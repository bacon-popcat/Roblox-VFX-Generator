---
name: ai-team
description: Run Claude, Codex and Gemini together on this project, with Claude as lead. Claude writes and previews, Codex reviews and fixes code, Gemini grades visuals against references. Use whenever the user asks to work with Codex and/or Gemini, wants a second opinion or cross-check from another AI, says "get the team on this", or asks for a review or grade by another model.
---

# AI team: Claude + Codex + Gemini

Claude leads. Codex and Gemini are helpers that Claude calls **one at a time**; their answers
come back to Claude, who decides, applies and verifies. Nobody acts in parallel.

| Who | Role | Gets |
|---|---|---|
| Claude | Lead: plans, writes effects (via `roblox-vfx`), drives Studio, applies changes | Everything |
| Codex | Code reviewer / second coder | Diffs, file paths, bug descriptions |
| Gemini | Visual judge, image/video analysis | Screenshots, side-by-side sheets, reference frames |

## Hard rules (all three)

1. **One Studio driver at a time.** While Claude is scrubbing, screenshotting or in Play mode,
   no helper touches Studio. If a helper needs Studio, Claude waits for it to finish first.
   Studio has no locking; the last writer wins.
2. **Edit files on disk only** (`src/`), never synced scripts in Studio. Rojo syncs them.
   Before testing, check the Studio script matches the file on disk.
3. **ForgeVFX is game-runtime only.** Never in any helper's command-bar or MCP snippet.
4. **Helpers advise; Claude verifies.** Read every helper diff (`git diff`) before keeping it,
   and re-check in Studio after a helper's change. A helper's report is not proof.
5. **Tell helpers what's out of scope**, so they don't "fix" intentional choices.

## Calling Codex

The Codex plugin runs the local Codex CLI (logged in with the user's ChatGPT account).

- Review / diagnosis (read-only): spawn the `codex:codex-rescue` agent and say "read-only,
  do not edit files" in the prompt. Example: "Review the uncommitted diff of
  `src/shared/VFX/Effects/LavaEruption.luau` for bugs, leaks, timing errors and violations of
  `.claude/skills/roblox-vfx/SKILL.md`. Read-only. List findings with file:line."
- Fix: same agent, without "read-only". Afterwards run `git diff` and review it yourself.
- Follow-up on the same thread: include `--resume` in the prompt so Codex keeps its context.
- Automatic review at the end of each turn: the user can turn on the review gate with
  `/codex:setup`.

## Calling Gemini

Needs the Gemini CLI. Check first: `gemini --version`. If it is missing, tell the user to run
`npm install -g @google/gemini-cli` and then `gemini` once to log in, and carry on without it.

Run it headless from the project folder, read-only (never pass `-y`/`--yolo`):

```bash
gemini -p "<prompt>" --approval-mode plan
```

(If the installed version rejects `--approval-mode plan`, drop the flag; never use `-y`.)
Attach images by path inside the prompt with `@`, e.g.
`@C:/Users/.../scratchpad/sheet_t0.30.png`. Keep images in the scratchpad.

Typical grading prompt:
"You are a strict VFX grader. Left = reference (ground truth), right = our Roblox effect at
the same timestamp. Score 1-10 on shape, colour, size, timing/position, and list concrete
differences, most important first. Out of scope: <list>. Images: @ref_sheet.png @ours_sheet.png"

Gemini fits the reference-grading workflow (see memory `vfx-reference-grading-workflow`):
use it as the grader, or as a second grader beside a Claude subagent, and compare the two.
Textures still go through Composio `GEMINI_GENERATE_IMAGE` (see `roblox-vfx` `references/textures.md`).

## Standard loop

1. Claude builds or changes the effect and previews it in Studio (`roblox-vfx` skill).
2. Claude captures frames / side-by-side sheets → **Gemini grades** the look.
3. Claude fixes the visual issues, then → **Codex reviews** the code diff.
4. Claude applies or rejects each finding, re-previews, and commits.
5. Report to the user who found what, and what was or wasn't adopted and why.

Skip helpers that add nothing: a one-line tweak doesn't need a Codex review, and a
code-only change doesn't need Gemini.
