---
name: ai-team
description: Run Claude and Codex together on this project, with Claude as lead. Claude writes, previews and grades effects; Codex reviews and fixes code. Use whenever the user asks to work with Codex, wants a second opinion or cross-check from another AI, says "get the team on this", or asks for a review by another model.
---

# AI team: Claude + Codex

Claude leads. Codex is a helper that Claude calls **one task at a time**; its answers come
back to Claude, who decides, applies and verifies. Claude and Codex never act in parallel.
The one other AI is **agy** (Antigravity CLI, Gemini), used only to grade effects against
reference frames (see `roblox-vfx` `references/structure.md`, "Matching a reference video").
Do not bring in other AI CLIs, or give agy other roles.

| Who | Role | Gets |
|---|---|---|
| Claude | Lead: plans, writes effects (via `roblox-vfx`), drives Studio, grades visuals, applies changes | Everything |
| Codex | Code reviewer / second coder | Diffs, file paths, bug descriptions |
| agy | Reference grader | Side-by-side comparison sheets, grading prompt |

## Hard rules

1. **One Studio driver at a time.** While Claude is scrubbing, screenshotting or in Play mode,
   Codex doesn't touch Studio. If Codex needs Studio, Claude waits for it to finish first.
   Studio has no locking; the last writer wins.
2. **Edit files on disk only** (`src/`), never synced scripts in Studio. Rojo syncs them.
   Before testing, check the Studio script matches the file on disk.
3. **ForgeVFX is game-runtime only.** Never in a command-bar or MCP snippet, Codex's included.
4. **Codex advises; Claude verifies.** Check every finding against the code before reporting
   it, read every Codex diff (`git diff`) before keeping it, and re-check in Studio after a
   Codex change. A Codex report is not proof.
5. **Tell Codex what's out of scope**, so it doesn't "fix" intentional choices (e.g. numbers
   tuned against a reference video).

## Calling Codex

The Codex plugin runs the local Codex CLI (logged in with the user's ChatGPT account).

- Review / diagnosis (read-only): spawn the `codex:codex-rescue` agent and say "read-only,
  do not edit files" in the prompt. Example: "Review the uncommitted diff of
  `src/shared/VFX/Effects/LavaEruption.luau` for bugs, timing-track ordering, leaks and
  violations of `.claude/skills/roblox-vfx/SKILL.md`. Read-only. List findings with file:line,
  a failing scenario and a fix."
- Fix: same agent, without "read-only". Afterwards run `git diff` and review it yourself.
- Follow-up on the same thread: include `--resume` in the prompt so Codex keeps its context.
- Automatic review at the end of each turn: the user can turn on the review gate with
  `/codex:setup`.

## Standard loop

1. Claude builds or changes the effect and previews it in Studio (`roblox-vfx` skill).
2. Claude grades the look itself, or, when there is a reference, has agy grade it against
   the reference frames (see memory `vfx-reference-grading-workflow`), and fixes visual issues.
3. **Codex reviews** the code diff.
4. Claude verifies each finding, applies or rejects it (asking the user when a fix would
   change the look), re-previews, and commits.
5. Report to the user what Codex found, what was confirmed, and what was or wasn't adopted
   and why.

Skip Codex when it adds nothing: a one-line tweak or a comment change doesn't need a review.
