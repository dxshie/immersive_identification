# AGENTS.md

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

- `gamedata/scripts/ii_identify.script` — coordinator: callbacks, modes, target selection,
  and the public interface used by MCM and compatibility components.
- `gamedata/scripts/ii_config.script` — defaults, menu lists, and configuration loading.
- `gamedata/scripts/ii_frame.script` — per-update caches for engine queries and geometry.
- `gamedata/scripts/ii_visibility.script` — geometric LOS and reusable ray state.
- `gamedata/scripts/ii_tracking.script` — admission, stable slots, and reveal lifecycle.
- `gamedata/scripts/ii_ui.script` — widget creation, measurement, placement, and drawing.
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
- `nix run .#check-lua` — headless lua-language-server check. **Does NOT catch the
  200-local limit** (see below) — that's a real-compiler error the LSP misses.
- `nix run .#format` — StyLua-format every `.script` (config in `stylua.toml`).
  StyLua globs `.lua`, so the app passes the `.script` files explicitly.
- `nix run .#check-format` — verify formatting without writing (CI-friendly).
- `nix run .#check-i18n` — verify eng/rus string-table **parity + windows-1251 encoding**. Run
  after any string-table edit. See the **`translation-sync`** skill for the string-id rules.
- `nix run .#package` — build the FOMOD zip (version read from `fomod/info.xml`).

`.luarc.json` maps `*.script` → Lua so the LSP treats Anomaly scripts as Lua 5.1.
`stylua.toml` uses tabs + a wide column to match the hand-written style.

**Keep docs/translations in sync (project skills in `.agents/skills/`):** the
**`translation-sync`** skill fires when you touch any string table (eng ⇄ rus parity, cp1251,
path-derived MCM ids); the **`spec-sync`** skill fires when you change behaviour/config that
`SPEC.md` documents (esp. the §4 setting inventory, which must match DEFAULTS + MCM + presets +
`MCM_PAGES`).

## Lua 5.1 gotcha: the 200-local-per-chunk limit

`ii_identify.script` is a single large chunk and **Lua 5.1 hard-caps a function at 200
local variables** (the file's top level *is* the "main function"). Cross it and the mod
**fails to load** with `main function has more than 200 local variables` — and because
`ii_identify` never registers, MCM then crashes on entry (`Register_List` indexes a nil
list). This has bitten the mod **twice**.

- **lua-language-server does NOT flag it.** The only reliable check is the real compiler:
  ```
  nix shell nixpkgs#lua5_1 --command luac -p gamedata/scripts/ii_identify.script
  ```
  Run this after any change that adds **top-level** state. (Function-local variables and
  `for`-loop vars don't count toward the limit — only the chunk's top-level `local`s do,
  and they never go out of scope so they accumulate.)
- **Every top-level `local X, Y = ...` counts each name separately.**
- **Convention: bundle new module-level state into ONE table**, e.g.
  `local _v = { p = vector2(), scratch = vector(), ... }` (scratch vectors),
  `local PIP_MARKER = { radius = .03, lift = .22, ... }` (constant groups),
  `local _ads_dwell = { armed = false, start = 0, ... }` (feature state) — rather than
  adding bare `local`s. Prefer tables by default when adding new top-level state.

## Code style & engineering practices (apply to all code work here)

**Comments — the *why*, not the *what*.** Don't comment self-explanatory code; a comment
that restates the code is noise, delete it. Comment ONLY: edge cases, non-obvious or
opaque behavior, engine gotchas, and the reason behind a non-obvious choice/workaround.
Let good names and small functions carry the "what." (Much of the older code here is
densely commented; new and changed code follows this leaner rule — do not match the old
density.)

**Naming & structure.** Intention-revealing names; keep the existing conventions
(`snake_case` locals/functions, `SCREAMING_SNAKE` constants, `_`-prefixed module scratch).
Small single-purpose functions; early-return over deep nesting; no dead/commented-out code.

**Scope related state into a table/struct, not loose variables.** When several values
share a context, model them as one table (`_ads_dwell = { armed, start, last }`,
`PIP_MARKER = { radius, lift, ref, ... }`, `_v` for shared scratch) instead of a spray of
parallel locals. It reads honestly and keeps the top-level-local count down (see above).

**Avoid Lua 5.1 performance pitfalls** — the mod runs every frame in `actor_on_update`,
so hot paths are real. If unsure whether something is hot or costly, check before adding
it to a per-frame path.
- **No table/vector allocation in per-frame or hot loops** — reuse scratch (`_v.*`,
  `active_pool`, the reused box lists). Per-frame GC churn is the single biggest cost.
- **Localize hot globals / library functions** (`local floor = math.floor`) and **hoist
  repeated lookups out of loops** (`local pos = obj:position()` once). Every `a.b.c` and
  every bare global is a hash lookup.
- **Build strings with a list + `table.concat`**, never `..` in a loop (each `..`
  allocates a new string).
- **`t[#t+1] = v`** over `table.insert` in hot code; never `#t` on a table with `nil`
  holes (its length is undefined).
- **Throttle expensive engine calls** (raycasts, `level.iterate_nearest`, LOS/`see`) on a
  ms timer instead of running them every frame — the mod already does; keep that pattern.
- **`pcall` has real cost** — guard at a boundary, don't wrap tight inner loops in it.
