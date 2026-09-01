# CLAUDE.md

## What this is

**Immersive Identification** — a S.T.A.L.K.E.R. Anomaly / GAMMA mod for the X-Ray
(xray-monolith) engine, written in Lua 5.1. The player aims at an NPC/creature and
presses an identify key; after a short "scanning" pulse a **world-anchored floating
card** appears on the target showing its faction, name, rank, and optionally its
weapon. It replaces static HUD faction indicators with a diegetic, in-world label
that tracks the target. Identification is fully deterministic (no RNG) — distance,
rank, darkness, binoculars, perception skill, and familiarity only change how long
the scan takes.

## Read the spec first

**[SPEC.md](./SPEC.md)** is the full technical spec — architecture, the per-tag
state machine, target selection, the scan-time multiplier chain, UI rendering, the
complete MCM setting table, assets, the FOMOD installer, and the compatibility
add-ons. Start there before changing anything.

## Layout at a glance

- `gamedata/scripts/ii_identify.script` — core runtime: all logic **and** UI.
- `gamedata/scripts/ii_mcm.script` — MCM settings menu (reads defaults/lists from
  `ii_identify.script` as the single source of truth).
- `gamedata/configs/` — string table (`text/`), UI widget templates (`ui/ii_tags.xml`),
  texture registration (`ui/textures_descr/`).
- `fomod/` — installer; base mod plus optional **FactionID Neutralized** and
  **Perception Skill Integration** components.
- `types/` — EmmyLua engine stubs for the LSP.

## Engine API bindings

The Lua ↔ engine bindings (luabind exports: `level.*`, `game_object`, `db.actor`,
callbacks, UI classes, etc.) are defined in the **xray-monolith engine source by
demonized** — look them up there rather than guessing:
**https://github.com/themrdemonized/xray-monolith**

Grep the C++ source for a symbol to confirm exact signatures/behavior before relying
on it; the `types/` stubs are cited against that source but engine forks drift.

## Dev tooling (nix flake)

- `nix run .#check-xml` — `xmllint --noout` over all mod XML. **Run after any XML
  comment edit** — a bare `--` inside an XML comment crashes the engine's loader and
  xmllint is the only thing that reliably catches it.
- `nix run .#check-lua` — headless lua-language-server check.
- `nix run .#package` — build the FOMOD zip (version read from `fomod/info.xml`).

`.luarc.json` maps `*.script` → Lua so the LSP treats Anomaly scripts as Lua 5.1.
