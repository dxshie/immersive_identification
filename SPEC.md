# Immersive Identification — Technical Specification

> **Version:** 2.0.0 &nbsp;•&nbsp; **Engine:** X-Ray / xray-monolith (S.T.A.L.K.E.R. Anomaly / GAMMA), Lua 5.1
> **Repo:** https://github.com/dxshie/immersive_identification

This document describes how the mod is architected and behaves. It is derived
from a full read of the source; file:line citations point into the current tree.

---

## 1. What the mod does

The player aims at an NPC, creature, or stalker and presses an identify key
(default `DIK_X`). After a brief "scanning" pulse, a **world-anchored floating
card** appears attached to the target's body, naming its **faction, personal
name, rank**, and optionally its **held weapon**. The card fades in, holds for a
configurable duration, then fades out.

It replaces static HUD faction indicators (e.g. the FactionID mod) with a
diegetic, in-world label that tracks the target as it and the camera move.

Two visual styles:

- **Card** (`ui_style = 1`): dark plate + faction icon + text lines + a leader
  line connecting to a colored dot on the target's chest.
- **Minimal** (`ui_style = 2`): just a faction-colored dot plus a relation glyph
  (`-` enemy / `+` friend / `o` neutral).

Identification difficulty is expressed **entirely as reveal delay** (scan time),
not as pass/fail. **There is no RNG anywhere** — the outcome is fully
deterministic; distance, rank, darkness, binoculars, perception skill, and prior
familiarity only speed up or slow down how long the scan takes.

---

## 2. Repository layout

```
gamedata/
  scripts/
    ii_identify.script          Core runtime (~1672 lines): logic + UI
    ii_mcm.script               MCM settings-menu definition (~119 lines)
  configs/
    text/eng/st_ii_texts.xml    String table (windows-1251)
    ui/ii_tags.xml              CUIStatic widget templates for the card
    ui/textures_descr/ii_textures.xml   Texture id -> file registration
  textures/ui/*.dds             ii_white, ii_dot, ii_node, ii_spinner, ii_shadow
fomod/
  info.xml                      Name/Author/Version 2.0.0/Website
  ModuleConfig.xml              Installer: base + 3 optional components
FactionID Neutralized/          Optional: no-op override of FactionID's HUD script
Perception Skill Integration/   Optional: adds a "perception" skill to Skill System
types/                          EmmyLua engine stubs for the LSP
flake.nix, .luarc.json          Nix dev tooling (xmllint / LuaLS / packaging)
```

The mod installs as a `gamedata/` overlay merged over the base game via Mod
Organizer 2's virtual file system. Compatibility add-ons are pure VFS overlays —
neither edits a host mod's files.

---

## 3. Runtime architecture (`ii_identify.script`)

### 3.1 Lifecycle / entry points

`on_game_start()` (1665-1672) is the sole bootstrap:

1. `read_config()` — load MCM/defaults (1666)
2. `install_key_hook()` — wrap `level_input.on_key_press` (1667)
3. Register four multi-subscriber callbacks (1668-1671): `actor_on_update`,
   `on_option_change`, `save_state`, `load_state`.

- **Key hook** (`install_key_hook`, 983-998): monkey-patches
  `level_input.on_key_press`, saving the previous handler and chaining to it via
  `pcall` so it **cooperates** with other mods rather than seizing the single
  native slot. On a matching DIK + modifier (and `not disabled`) it calls
  `try_identify()`.
- **Per-frame driver** (`actor_on_update`, 1619-1632): always runs
  `update_fov_baseline()`; then when enabled runs `ensure_tags()`,
  `update_binocular_scan()`, `update_loot_xp()`, and `render()`.
- **Render surface** (`ensure_tags`, 1446-1453): lazily creates the `IiTags`
  (`CUIScriptWnd`) dialog and registers it with `get_hud():AddDialogToRender()`.
  There is **no separate render callback** — drawing is done by repositioning
  persistent widgets each `actor_on_update` frame.
- **`on_option_change`** (1661-1663) re-reads config live when MCM changes.
- **`save_state` / `load_state`** (1646-1656) persist `xp_awarded`, `remembered`,
  `loot_xp_awarded`. Live reveal state (`tracked`) is intentionally not saved.
  Callbacks are declared `local` to avoid clobbering same-named globals in other
  scripts.

### 3.2 State machine

Central table `tracked` (190): `[obj_id] = { t0, col, fcol, sign, header, name,
icon, rank, weap, scan_ms, max_dist, fade_dist, fade_ms, hold_ms }`, capped at
`MAX_TAGS = 5` (8). When full, the oldest entry (lowest `t0`) is evicted before
insert (905-910).

Each entry runs a **time-based state machine** keyed on
`elapsed = time_global() - t0`, evaluated every frame in `render()` (1518-1534).
`total = scan_ms + fade_ms + hold_ms + fade_ms`:

| Phase | Condition | Visual |
|---|---|---|
| Scanning | `elapsed < scan_ms` | rotating spinner only, alpha 0 |
| Fade-in | `< scan_ms + fade_ms` | alpha ramps 0 → 1 |
| Hold | `< scan_ms + fade_ms + hold_ms` | full card, alpha 1 |
| Fade-out | else | alpha 1 → 0 |
| Removed | `elapsed > total`, or object gone/dead | — |

**Snapshot-at-identify:** all timing/range params are frozen into the `tracked`
entry at identify time (912-926) and read from the entry during render
(1505-1509), so live MCM edits or lowering binoculars mid-reveal never
retroactively distort an in-progress card.

**Re-identify while tracked** (881-898) restarts the reveal by resetting `t0` and
refreshing every snapshot, so the familiarity discount (2nd+ identify) takes
effect immediately rather than waiting for the current card to clear.

### 3.3 Target selection

`get_target_obj(max_dist)` (491-516) — a three-tier cascade:

1. Weapon-aligned trace: `level.get_target_obj(level.ETraceTarget.Weapon)` (500)
2. Camera trace fallback: `level.get_target_obj()` (503)
3. FOV fallback: `find_nearest_in_fov(max_dist)` — **only if FOV assist is enabled
   for the current context**. `try_identify` passes `allow_fov`, which is
   `fov_assist_binoc` while looking through raised binoculars and `fov_assist`
   otherwise. With it off, identification is direct-hit only (tiers 1–2).

Both raycasts are **LOS-gated** via `accept()` → `has_los()` because the engine's
crosshair pick sees *through* semi-transparent geometry (fences/glass/foliage)
and can return an occluded object (comment 481-490). `has_los` is a **two-layer
check, both must pass**:

1. `db.actor:see(target)` — the engine's camera-driven perception check
   (darkness/stealth aware). It is smoothed/cached with a short grace window, so
   on its own it lets a target that just stepped behind a wall (or one the AI
   still "remembers") read as visible for a beat.
2. `has_clear_ray(target)` — a fresh geometric `ray_pick` raycast against
   **static** world geometry (`rqtStatic`) from the target's anchor point toward
   the camera. This is the hard backstop that closes see()'s grace-window leak
   through solid geometry. `query()` returns true when occluded, so a clear line
   is `not query()`. Trade-off: solid-collision fences/foliage block even when
   see-through; acceptable for the common "behind a building" case.

Both layers **fail open** (return visible) if their engine call errors or the
`ray_pick` binding is absent, so LOS gating degrades gracefully rather than
blocking all identification.

`find_nearest_in_fov` (440-468) iterates `level.iterate_nearest`; a candidate
must be non-actor, `IsStalker` or `IsMonster`, alive, have a non-empty
`character_community`, and (if `require_los`) pass LOS. It selects the candidate
**nearest to screen center** (crosshair at virtual 512,384) within `fov_radius`,
not nearest in world space. Already-tracked targets are held as a runner-up and
only returned if nothing else qualifies.

### 3.4 Scan-time computation

`try_identify()` (833-927) commits immediately on a valid target; the visible
delay `eff_scan_ms` is `SCAN_MS` multiplied through a chain of factors:

| Factor | Function | Range |
|---|---|---|
| Distance | `distance_scan_mult` (574-579) | 1× point-blank → `dist_penalty_max` at cutoff |
| Rank | `rank_scan_mult` (618-625) | 1× novice → `rank_penalty_max` legend, via `RANK_WEIGHT` (600-609) |
| Night | `night_scan_mult` (663-666) | 1× day → `night_penalty_max`, scaled by `darkness_factor` (651-658), peaks 23:00–04:00 |
| Binoculars | `binoc_scan_mult` (871) | flat multiplier while raised (if `binoc_boost`) |
| Perception | `perception_scan_mult` (690-696) | `1 − perception_scan_mult × level`, floored at 0.15 |
| Familiarity | `familiarity_scan_mult` (877-879) | applied if `remembered[id]` |

Gating (834-857): `enabled` + actor exists; if `require_binoculars`,
`is_binoc_active()` must be true; target exists, is not the actor, is alive, has a
community, and is within `eff_max_dist`.

### 3.5 Binoculars

- `is_binoc_held()` (522-529): `active_item():section()` contains
  `BINOC_SECTION = "wpn_binoc_inv"`.
- `is_binoc_active()` (557-563): additionally requires camera FOV to have dropped
  below `FOV_ZOOM_RATIO (0.7) × _fov_baseline`; the baseline self-calibrates each
  frame from the widest FOV seen while binoculars aren't held
  (`update_fov_baseline`, 548-555).
- `binoc_boost` widens `eff_max_dist` / `eff_fade_dist` by `binoc_range_mult`
  (842-844) and speeds the scan.
- **Auto-identify** (`update_binocular_scan`, 949-981): when `binocular_mode` and
  binoculars active, tracks a "steady" camera direction against an anchor
  (`STEADY_MAX_D2 = 0.002`, ~2.6°); held steady for `steady_time`, it auto-fires
  `try_identify()` once (`steady_triggered` guard).

### 3.6 UI rendering

`IiTags : CUIScriptWnd` (1019), rect 1024×768, parses `ii_tags.xml` via
`CScriptXmlInit`. `InitControls` (1025-1073) builds `MAX_TAGS` slots of widgets in
draw order (shadow → line → plate → accent → icon → text → node/glow → spinner).

- **World-to-screen:** `anchor_pos(obj)` (379-390) picks the first of
  `ANCHOR_BONES` (`bip01_head`, `bip01_spine2/1`, `bip01_spine`) within 3m and
  lifts by `ANCHOR_LIFT = 0.12`; monsters fall back to `position().y + 1.3`.
  `project_world` (392-398) calls `game/level.world2ui`, rejecting `x < -9000`
  (off-screen/behind).
- **`draw_slot`** (1194-1441) branches: scanning spinner only → minimal
  (node+glow+glyph) → mini fallback below `mini_scale_cutoff` (node+glow) → full
  card (measured text, plate, accent, icon, shadowed text lines, node/glow, and a
  leader line rotated via `atan2`/`SetHeading` from node to the card's nearest
  bottom corner).
- **Aspect correction** `UI_KX` (200): `(h/w)/(768/1024)`; the X of any
  KX-distorted static (node, glow, line) is pre-corrected so circles stay round
  and angles stay true under the engine's anisotropic virtual→screen stretch. The
  spinner is deliberately kept square (rotation doesn't commute with non-uniform
  scale).
- **Overlap avoidance** (`render` 2nd pass, 1589-1612): a card whose anchor is
  within `STACK_DIST_X=140` / `STACK_DIST_Y=90` of an earlier card is pushed
  `stack × STACK_STEP (58)` px higher.
- **Picture-in-Picture scope path** (1476-1587): gated on `PIP_AVAILABLE` (soft
  existence check via `rawget` of `is_svp_active` / `svp_ui_markers_*`). When a
  scope is raised it submits in-scope world markers and hides the normal HUD slots
  so a mis-projected main-camera card doesn't clash with the scope view.

### 3.7 Rewards / familiarity

- First identify of a target awards `perception_xp` once (`xp_awarded` gate) and
  sets `remembered[id]` (900-903).
- `update_loot_xp` (812-831) awards `perception_loot_xp` the first time you loot a
  corpse you had already identified, detected by polling `get_talking_npc()` for a
  set→cleared transition (`loot_xp_awarded` gate).
- `award_perception_xp` (764-770) writes `haru_skills.skills_levels.perception
  .experience` directly (deliberately not `increase_skill`, which would throw on a
  non-base skill).

### 3.8 Notable functions

`read_config` (214) • `active_dik` (240) • `modifiers_ok` (254) •
`faction_label/color` (272) • `display_name` (290) • `rank_label` (309) •
`held_weapon_label` (331) • `relation_color/sign` (357) • `anchor_pos` (379) •
`project_world` (392) • `has_los` (422) • `find_nearest_in_fov` (440) •
`get_target_obj` (491) • `is_binoc_active` (557) • `distance_scan_mult` (574) •
`rank_scan_mult` (618) • `darkness_factor` (651) • `perception_scan_mult` (690) •
`perception_hint_stats` (722, exposed as global for the Skill System tooltip) •
`update_loot_xp` (812) • `try_identify` (833) • `update_binocular_scan` (949) •
`install_key_hook` (983) • `IiTags:draw_slot` (1194) • `render` (1472) •
`on_game_start` (1665).

---

## 4. Configuration (MCM — `ii_mcm.script`)

MCM auto-discovers `on_mcm_load` only in files ending `mcm.script`, so the menu
lives here while logic stays in `ii_identify.script`. **Single source of truth:**
defaults, the modifier dropdown, and the UI-style dropdown are read from
`ii_identify.DEFAULTS` / `MODIFIER_LIST` / `UI_STYLE_LIST` (11-25). The key-bind
default is resolved here (not in `DEFAULTS`) because `DIK_keys` isn't populated
when `ii_identify.script` is first parsed (27-31).

**Tree:** root node `id="ii"` (no `sh`) → one leaf page `id="main"` (`sh=true`)
holding a `gr` of options. Section headers are `type="slide"` pseudo-entries. Two
MCM traps are encoded in comments: the top node must **not** carry `sh` (only the
leaf page does), and `hint` ids must be passed **bare** because MCM auto-prepends
`ui_mcm_`.

### Setting inventory

| id | type | default | range (min,max,step,prec) | controls |
|---|---|---|---|---|
| `enabled` | check | true | — | master on/off |
| `key_dik` | key_bind | `DIK_X` | — | identify key |
| `modifier_index` | list | None | None/Ctrl/Shift/Alt | required held modifier |
| `ui_style` | list | Card | Card/Minimal | card vs minimal dot |
| `color_by_relation` | check | true | — | tint by relation vs flat neutral |
| `show_weapon` | check | false | — | add held-weapon line, with caliber appended when derivable (Card only) |
| `scan_time` | track | 0.35 | 0, 2, 0.05, 2 | base scan pulse (s) |
| `fade_time` | track | 0.45 | 0.1, 2, 0.05, 2 | fade in/out (s) |
| `hold_time` | track | 4.0 | 1, 15, 0.5, 1 | full-visible hold (s) |
| `max_dist` | track | 50 | 10, 500, 10 | max identify range (m) |
| `fade_dist` | track | 40 | 5, 500, 10 | distance where card fades (m) |
| `fov_assist` | check | true | — | master FOV target-assist; off = direct-hit aim only |
| `fov_radius` | track | 110 | 20, 400, 10 | target-assist radius (px) |
| `require_los` | check | true | — | require line of sight |
| `fov_assist_binoc` | check | true | — | FOV assist while looking through raised binoculars |
| `binocular_mode` | check | false | — | steady-aim auto-identify via binocs |
| `require_binoculars` | check | false | — | restrict identify to raised binocs |
| `steady_time` | track | 0.6 | 0.2, 3, 0.1, 1 | steady-aim hold time (s) |
| `binoc_boost` | check | true | — | binocs speed up + extend range |
| `binoc_scan_mult` | track | 0.4 | 0.1, 1, 0.05, 2 | scan-speed mult w/ binocs |
| `binoc_range_mult` | track | 2.5 | 1, 5, 0.1, 1 | range mult w/ binocs |
| `card_scale` | track | 1.0 | 0.5, 2, 0.05, 2 | flat card size multiplier |
| `mini_scale_cutoff` | track | 0.4 | 0.1, 1, 0.05, 2 | below this scale → dot only |
| `dist_penalty` | check | true | — | distance slows scan |
| `dist_penalty_max` | track | 5.0 | 1, 6, 0.1, 1 | scan mult at max range |
| `rank_penalty` | check | true | — | rank slows scan |
| `rank_penalty_max` | track | 3.0 | 1, 6, 0.1, 1 | scan mult for legend |
| `night_penalty` | check | true | — | darkness slows scan |
| `night_penalty_max` | track | 2.0 | 1, 6, 0.1, 1 | scan mult at darkest |
| `familiarity_boost` | check | true | — | remember identified stalkers |
| `familiarity_scan_mult` | track | 0.6 | 0.1, 1, 0.05, 2 | scan mult for familiar target |
| `perception_compat` | check | true | — | Skill System perception integration |
| `perception_scan_mult` | track | 0.04 | 0, 0.1, 0.01, 2 | scan reduction per level |
| `perception_xp` | track | 20 | 0, 100, 5 | XP per identify |
| `perception_loot_xp` | track | 20 | 0, 100, 5 | bonus XP for first loot |

---

## 5. Assets & data files

### 5.1 UI templates (`ii_tags.xml`)

Root `<w>`; technique mirrors Immersive Quest Markers' card style. **Every image
widget uses `stretch="1"`** — this is load-bearing, not cosmetic: `stretch="0"`
is engine `tmNative` mode which ignores `SetWndSize()` and draws textures at
native pixel size (the historical "dot is huge" bug). Most textures ship white
and are tinted at runtime via `SetTextureColor`.

Image widgets: `tag_shadow` (80×40, ii_shadow), `tag_plate` (80×40, ii_white,
charcoal 24/22/19), `tag_accent` (3×26, relation bar), `tag_icon` (20×20, swapped
to `<community>_icon` at runtime), `tag_line`/`tag_line_sh` (64×2, leader line),
`tag_glow` (40×40, ii_dot), `tag_node` (10×10, ii_node, baked black ring),
`tag_spinner` (20×20, ii_spinner). Text widgets (each with a `_sh` shadow twin):
`tag_head` (letterica16, faction), `tag_name` (letterica18, personal name),
`tag_rank` (letterica16, hidden for monsters), `tag_weap` (letterica16),
`tag_sign` (letterica18, centered relation glyph for Minimal style).

### 5.2 Textures (`ii_textures.xml` → `textures/ui/*.dds`)

Each registers the whole file as one region. `ii_white` (32×32 solid),
`ii_dot` (64×64 soft AA circle, glow/pulse), `ii_node` (64×64 white fill with a
**baked black outline ring** so the ring survives any tint), `ii_spinner`
(128×128 comet-tail ring), `ii_shadow` (64×64 feathered rounded box). Textures
ship in-mod so the tag draws with zero external dependency.

### 5.3 String table (`st_ii_texts.xml`, windows-1251)

MCM menu labels; a `ui_mcm_ii_<id>` label + `ui_mcm_ii_<id>_desc` hint pair per
setting; section titles; dropdown entry ids (`ii_main_<option>_lst_<label>`); and
16 faction display names `st_ii_faction_<community>` (Loner, Bandits, Duty,
Freedom, Clear Sky, Ecologists, Mercenaries, Military, Monolith, Renegades,
Zombified, Sin, Trader, Mutant, UNISG, Arena).

---

## 6. Installer & optional components (`fomod/`)

**info.xml:** Immersive Identification, **v2.0.0**, group Gameplay.

**ModuleConfig.xml** (ModConfig 5.0):

- **Required:** `gamedata → gamedata` (self-contained drop-in, no required
  choices).
- **One step** "Optional Components" → group "Compatibility" (`SelectAny`), two
  optional plugins (all unchecked by default):
  1. **Neutralize FactionID HUD** → installs `FactionID Neutralized/gamedata`.
  2. **Skill System: Perception** → installs `Perception Skill Integration/gamedata`.

---

## 7. Compatibility add-ons

### 7.1 FactionID Neutralized

A single file `factionID_hud_mcm.script` that **overrides** FactionID's own
same-path script (VFS "last-mod-wins") with an inert stub — every public function
(`activate_hud`, `identify`, `actor_on_update`, `on_mcm_load`, `on_game_start`, …)
redefined as a no-op, `HUD = nil`. This suppresses FactionID's on-screen HUD so
you don't get two overlapping faction indicators, while leaving the rest of that
mod harmlessly loaded. Only relevant if FactionID is installed.

### 7.2 Perception Skill Integration

A soft-compat overlay for the third-party **Skill System (`haru_skills`)** mod.
Ships **no scripts** — all logic is in `ii_identify.script`; these are pure
config/asset files plugged in through haru_skills' own wildcard `#include` VFS
overlays, with **zero edits** to the host mod:

- `skills/skill_perception.ltx` — `[perception]` `max_level=15`,
  `base_requirement=600` (picked up by `#include "skill_*.ltx"`); an inert
  `[perception_stats]` block exists only because haru_skills reads a
  `<skill>_stats` section for every skill.
- `skills/ui_settings/stats_perception.ltx` — wires the stat to a live functor
  `functor = ii_identify, perception_hint_stats` (via `#include "stats_*.ltx"`).
- `text/eng/st_ii_skill_perception_texts.xml` — `st_player_skills_perception`,
  its hint, the level-up toast, and a dynamic `st_ii_perception_hint_stats`
  template (`$level`, `$t1..$t4` filled by `perception_hint_stats()` showing live
  scan times at point-blank / max-range / binocular combos).
- `ui/textures_descr/ii_skill_perception_textures.xml` + `ii_skill_perception.dds`
  — registers `ui_skills_icon_perception` (96×96) on a standalone file following
  haru_skills' `ui_skills_icon_<skill>` convention.

Without this component (and the host mod) there is no XP and no effect.

---

## 8. Dev tooling

- **`flake.nix`** — `devShells.default` provides `xmllint` (libxml2),
  `lua-language-server`, `lua5_1`, `p7zip`. Three apps: **`check-xml`** runs
  `xmllint --noout` over all mod XML (guards the recurring bare-`--`-in-XML-comment
  crash), **`check-lua`** runs LuaLS headless at Warning level, **`package`**
  reads `<Version>` from `info.xml` and zips a FOMOD bundle.
- **`.luarc.json`** — Lua 5.1 runtime, `workspace.library=["types"]` for the
  EmmyLua engine stubs, and the key association trick
  `"files.associations": { "*.script": "lua" }` so LuaLS treats Anomaly's
  `.script` files as Lua and gives them diagnostics/completion.

---

## 9. Design principles (cross-cutting)

- **No RNG — difficulty is reveal delay.** Every "penalty" is a scan-time
  multiplier; identification always succeeds if the target is valid and in range.
- **Snapshot-at-identify.** Timing/range are frozen per-tag so live setting or
  binocular changes never distort an in-progress reveal.
- **Cooperative, not exclusive, hooks.** `level_input.on_key_press` is chained;
  binocular/loot detection uses polling and an FOV baseline instead of contended
  single-slot native callbacks.
- **Soft dependencies, two ways.** Engine C++ globals (`svp_*` PiP) are checked
  via `rawget` at load; Lua script globals (`haru_skills`) are nil-chained at call
  time (load order isn't guaranteed).
- **Single source of truth.** MCM, string ids, and dropdown entry ids are all
  derived from `ii_identify.script`'s `DEFAULTS`/lists and MCM's id-resolution
  rules.
- **Compat via pure VFS overlays.** FactionID via same-path script override;
  Perception via haru_skills' wildcard includes and naming conventions — neither
  edits a host mod.

---

## 10. Known repo drift (flagged during analysis)

- **`README.md`** — verify its optional-component list matches the two components
  currently in `ModuleConfig.xml` (FactionID Neutralized, Perception Skill
  Integration).
