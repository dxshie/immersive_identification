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

Three visual styles:

- **Card** (`ui_style = 1`): dark plate + faction icon + text lines + a leader
  line connecting to a colored dot on the target's chest.
- **Minimal** (`ui_style = 2`): just a faction-colored dot plus a relation glyph
  (`-` enemy / `+` friend / `o` neutral).
- **Bodycam** (`ui_style = 3`): an unfilled faction-colored rectangle outline
  locked to the target's **head bone**, auto-scaled with distance so it stays a
  constant real-world size around the head (a bounding box with padding). Four
  thin `ii_white` strips per edge (`draw_head_box`), with the target **name** and
  **weapon/caliber** (`e.weap`, includes caliber) stacked as shadowed text just to
  the right of the box (reusing the card's `tag_name`/`tag_weap` widgets). The box
  covers the head or the full body per **`box_area`** (`area_box_for`, shared with
  redaction). The head box is the **screen bounding box of the head's four
  projected corners** (`screen_box`: `center ± cam_right*BOX_HALF_W ±
  cam_top*BOX_HALF_H`), perspective-correct at any screen position — a
  single-axis extent shortcut mis-sizes/mis-centres near the screen edges (the
  "slips off at the corners" bug). The centre is `bip01_head` lifted `HEAD_LIFT`
  (0.09 m) to the face (the bone sits at the skull base, so an unlifted box rides
  low over the neck). Distance scaling falls out of the projection (no `UI_KX`
  squeeze). Pairs naturally with **Auto-identify** below.

Optionally, **Auto-identify** (`auto_identify`, default off) continuously reveals
every visible target in range without a keypress: a throttled
`level.iterate_nearest` sweep (`update_auto_identify`) hands each alive,
community-tagged, LOS-visible target to the shared `identify_target` commit path.
Line of sight is always required for it. Works with any style.

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

`find_nearest_in_fov` iterates `level.iterate_nearest`; a candidate must be
non-actor, `IsStalker` or `IsMonster`, alive, have a non-empty
`character_community`, and (if `require_los`) pass LOS. It selects the candidate
**nearest to the aim point** within `fov_radius`, not nearest in world space.
Already-tracked targets are held as a runner-up and only returned if nothing
else qualifies.

The aim point comes from `aim_center()`: the fixed screen center (512,384) by
default, or — when `freeaim_assist` is on — the projection of
`level.get_target_pos(ETraceTarget.Weapon)` (a world point along the actual
rendered weapon barrel, so it follows a **bodycam/free-aim** engine's off-center
barrel) via `weapon_aim_ui()`. It falls back to screen center whenever the
weapon-aim point is unavailable (no weapon in hand → `(0,0,0)`, the
`get_target_pos` binding is absent, or the point is off-screen). The direct-hit
tiers already trace `ETraceTarget.Weapon`, so they follow free aim regardless of
this toggle; `freeaim_assist` only redirects the FOV-assist circle.

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
- **Auto-identify** (`update_binocular_scan`): when `binocular_mode` **or**
  `ads_mode` is active, tracks a "steady" camera direction against an anchor
  (`STEADY_MAX_D2 = 0.002`, ~2.6°); held steady for `steady_time`, it auto-fires
  `try_identify()` once (`steady_triggered` guard).

### 3.5b Aim Down Sight (ADS)

Mirrors the binocular boost for regular weapons. `is_ads_active()` prefers the
bodycam engine's real aim flag (`bodycam.get_state().ads`, catches iron sights),
falling back to the same FOV-zoom heuristic with a gentler `ADS_ZOOM_RATIO (0.85)`;
binoculars are excluded so the two never stack. `boost_params()` now returns
`(binoc, ads, boosted, eff_max_dist, eff_fade_dist, scan_mult)` — binoc takes
priority, then ADS, each carrying its own `*_scan_mult` / `*_range_mult` from its
MCM section; `identify_target` applies the returned `scan_mult`. Its own MCM
section: `ads_mode` (steady-aim auto-identify), `ads_boost`, `ads_scan_mult`,
`ads_range_mult`, `ads_zoom_scaling`.

**Zoom-scaled range**: with `ads_zoom_scaling` on, the ADS range multiplier is
scaled by the current scope magnification — `range_mult = ads_range_mult × mag` —
so higher-power optics reach further (`ads_range_mult` is the x1 base). The magnification is **hybrid**, so it works with or without a PiP engine and
tracks dynamic zoom live in both: (1) on a PiP engine the zoom lives in the second
viewport (main FOV unchanged), so the new engine binding `svp_scope_magnification()`
— which returns the SVP `svp_mag` "zoom scaled trigger" (1.0=1x .. ~8x, -1 when not
scoped) — is the only accurate source; (2) with no PiP (or when the binding reports
nothing), a non-PiP optic narrows the **main-camera FOV**, so magnification is
recovered as `_fov_baseline / device().fov`. Iron sights / un-magnified aim stay at
the x1 base (`MAG_FOV_MIN = 1.05`).

**Zoom-out range cull** (`update_ads_range_cull`): on the ADS-boost
active→inactive edge, tags now beyond the (unboosted, base) range are dropped
immediately rather than lingering invisibly on their timer; survivors are
re-snapshotted to the base range. Deliberately ADS-only — binoculars keep a
just-glassed distant tag readable after lowering (observation vs. combat-aid UX).

**Steady auto-trigger uses auto semantics**: `try_identify(auto_mode)` — the
steady-aim trigger (binocular / ADS mode) passes `true`, so `identify_target`
refreshes an already-revealed target's hold window instead of restarting its
reveal. Without this, ADS combat aim (constant micro-adjustment re-arms the steady
trigger) re-scanned already-identified targets every re-fire — the "double
identification" retrigger, most visible in-scope as the marker flicking back to
the scanning spinner. A manual keypress (`nil`) still restarts on purpose.

**PiP toggles**: `pip_markers` gates the whole in-scope UI path (`pip_active =
pip_markers and PIP_AVAILABLE and is_svp_active()`) — off reverts to normal
HUD/main-pass behavior. `pip_redact` gates only the in-scope redaction, by zeroing
the world box extents in `glitch_submit` so the engine's SVP glitch pass skips
them (the main-view redaction is unaffected).

**Suppress main-view drawing**: `suppress_main = (ads_hide_main and is_ads_active())
or (pip_hide_main and pip_scope)` hides ALL main-view drawing — the HUD tags (adds
to the `pip_active or suppress_main` hide-slots-and-return) and the main-pass
redaction (`glitch_submit(…, main_off)` submits each box's main-camera rect
off-screen — outside `[0,1]`, so the main glitch shader finds no pixels — while the
WORLD box still feeds the in-scope pass). The in-scope UI is unaffected, so with a
PiP scope up you get in-scope-only rendering. `pip_scope` is the physical scope
state (independent of `pip_markers`), so this also covers `pip_markers`-off.

### 3.6 UI rendering

`IiTags : CUIScriptWnd` (1019), rect 1024×768, parses `ii_tags.xml` via
`CScriptXmlInit`. `InitControls` (1025-1073) builds `MAX_TAGS` slots of widgets in
draw order (shadow → line → plate → accent → icon → text → node/glow → spinner →
bodycam box edges).

- **World-to-screen:** `anchor_pos(obj)` (379-390) picks the first of
  `ANCHOR_BONES` (`bip01_head`, `bip01_spine2/1`, `bip01_spine`) within 3m and
  lifts by `ANCHOR_LIFT = 0.12`; monsters fall back to `position().y + 1.3`.
  `project_world` (392-398) calls `game/level.world2ui`, rejecting `x < -9000`
  (off-screen/behind).
- **`draw_slot`** branches: scanning spinner only → **bodycam** (head-outline
  box, `ui_style==3`) → minimal (node+glow+glyph, `ui_style==2`) → mini fallback
  below `mini_scale_cutoff` (node+glow) → full card (measured text, plate, accent,
  icon, shadowed text lines, node/glow, and a leader line rotated via
  `atan2`/`SetHeading` from node to the card's nearest bottom corner). The bodycam
  box's centre/extents (`box_cx/cy/hw/hh`) are precomputed per target in `render`
  (via `head_center` + `head_box_extents`) since `draw_slot` has no world access.
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

**Presets:** the leaf page carries a `presets = { "ii_card", "ii_minimal",
"ii_bodycam", "ii_immersive" }` list, which makes MCM show a preset dropdown at
the top of the page. Names resolve from `ui_mcm_prst_<id>` strings; **values live
in LTX**, not Lua — MCM reads `configs/presets/includes.ltx` (which we ship with a
wildcard `#include "presets_*.ltx"` so other mods coexist) → `presets_ii.ltx`,
whose `[<preset_id>]` sections key options by their storage path (`ii/main/<id>`,
values by type: check→bool, track/list→number). A preset only overrides the
options it lists. Adding an option to a preset = one LTX line; no code change.

**Tree:** root node `id="ii"` (no `sh`) → one leaf page `id="main"` (`sh=true`)
holding a `gr` of options, grouped by `type="slide"` section headers: **General**
(enable/key/instant/scan-fade-hold/hide-unseen/range), **UI Style** (style, box
area, show name/faction/weapon, colour-by-relation, card size), **Targeting**
(FOV assist, free-aim, LOS, auto-identify), **Binoculars**, **Redaction**, then
the scan-time modifier sections and Debug. Three MCM traps encoded in comments:
the top node must **not** carry `sh` (only the leaf page does); an option's
**`hint` is the BARE base id** (`"ii_<id>"`) — MCM resolves its caption from
`ui_mcm_<hint>` and its **hover tooltip** from `ui_mcm_<hint>_desc`, so passing a
`_desc`-suffixed hint mis-renders the label and kills the tooltip; and `text` is
only read for slide headers, not option captions. The `opt_check/opt_track/
opt_list` helpers set `hint = "ii_" .. id` mechanically.

### Setting inventory

| id | type | default | range (min,max,step,prec) | controls |
|---|---|---|---|---|
| `enabled` | check | true | — | master on/off |
| `key_dik` | key_bind | `DIK_X` | — | identify key |
| `modifier_index` | list | None | None/Ctrl/Shift/Alt | required held modifier |
| `ui_style` | list | Card | Card/Minimal/Bodycam | card vs minimal dot vs head-outline box |
| `box_area` | list | Head | Head/Body | bodycam outline rectangle region |
| `box_thickness` | track | 2 | 1, 6, 0.5, 1 | bodycam outline edge thickness (px) |
| `show_name` | check | true | — | show name line (all text styles) |
| `show_faction` | check | true | — | show faction line (all text styles) |
| `show_weapon` | check | true | — | show weapon+caliber line (all text styles) |
| `auto_identify` | check | false | — | continuously identify all visible in-range targets, no keypress (LOS always required) |
| `color_by_relation` | check | true | — | tint by relation vs flat neutral |
| `scan_time` | track | 0.35 | 0, 2, 0.05, 2 | base scan pulse (s) |
| `fade_time` | track | 0.45 | 0.1, 2, 0.05, 2 | fade in/out (s) |
| `hold_time` | track | 4.0 | 1, 15, 0.5, 1 | full-visible hold (s) |
| `max_dist` | track | 50 | 10, 500, 10 | max identify range (m) |
| `fade_dist` | track | 40 | 5, 500, 10 | distance where card fades (m) |
| `fov_assist` | check | true | — | master FOV target-assist; off = direct-hit aim only |
| `freeaim_assist` | check | false | — | bodycam/free-aim: center assist on weapon barrel, not screen center |
| `fov_radius` | track | 110 | 20, 400, 10 | target-assist radius (px) |
| `require_los` | check | true | — | require line of sight |
| `fov_assist_binoc` | check | true | — | FOV assist while looking through raised binoculars |
| `binocular_mode` | check | false | — | steady-aim auto-identify via binocs |
| `require_binoculars` | check | false | — | restrict identify to raised binocs |
| `steady_time` | track | 0.6 | 0.2, 3, 0.1, 1 | steady-aim hold time (s) |
| `binoc_boost` | check | true | — | binocs speed up + extend range |
| `binoc_scan_mult` | track | 0.4 | 0.1, 1, 0.05, 2 | scan-speed mult w/ binocs |
| `binoc_range_mult` | track | 2.5 | 1, 5, 0.1, 1 | max/fade distance mult w/ binocs |
| `ads_mode` | check | false | — | steady-aim auto-identify while ADS |
| `ads_boost` | check | true | — | ADS speeds up + extends range |
| `ads_scan_mult` | track | 0.6 | 0.1, 1, 0.05, 2 | scan-speed mult while ADS |
| `ads_range_mult` | track | 1.6 | 1, 5, 0.1, 1 | max/fade distance mult while ADS (x1 base) |
| `ads_zoom_scaling` | check | true | — | scale ADS range by scope magnification |
| `box_color_source` | list | 1 | faction, relation | bodycam box colour source |
| `pip_markers` | check | true | — | draw identification markers in a PiP scope |
| `pip_redact` | check | true | — | draw redaction in a PiP scope |
| `pip_hide_main` | check | false | — | hide all main-view drawing while a scope is up |
| `ads_hide_main` | check | false | — | hide all main-view drawing while aiming down sight |
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
`tag_spinner` (20×20, ii_spinner), `tag_box_top`/`tag_box_bottom`/`tag_box_left`/
`tag_box_right` (thin ii_white strips forming the Bodycam head-outline box, sized
per frame). Text widgets (each with a `_sh` shadow twin):
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
  `lua-language-server`, `lua5_1`, `stylua`, `p7zip`. Apps: **`check-xml`** runs
  `xmllint --noout` over all mod XML (guards the recurring bare-`--`-in-XML-comment
  crash), **`check-lua`** runs LuaLS headless at Warning level, **`format`** /
  **`check-format`** run StyLua over the `.script` sources (write / verify), and
  **`package`** reads `<Version>` from `info.xml` and zips a FOMOD bundle.
- **`stylua.toml`** — StyLua config: tabs, wide column (120), `AutoPreferDouble`,
  `call_parentheses="Always"`. StyLua globs `.lua`, so the format apps pass the
  `.script` files explicitly via `find`.
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

## 10. Free-aim support (bodycam engine)

The `freeaim_assist` setting makes the FOV target-assist circle follow where the
weapon actually points on a free-aim / bodycam engine
(`asuparabekon/xray-monolith-bodycam`) instead of the fixed screen center.

**The hard constraint: the free-aim direction must come from the engine.** In-game
diagnosis (via the `debug_log` MCM option) established that on the tested bodycam
build **neither** ordinary Lua source works:

- `level.ETraceTarget` / `level.get_target_pos(Weapon)` — **absent** on that build;
  and even where present it traces screen center, because free aim is applied in
  the render/ballistic layer, not the logical weapon pick the script sees.
- `bodycam.get_state()` — exposes only the **camera's** orientation
  (`camera_yaw ≈ atan2(cam_dir.x, cam_dir.z)`, `camera_pitch ≈ asin(cam_dir.y)`)
  and a ~zero `vm_rot`. None of it encodes the weapon's offset from center.

So the aim direction is **C++-internal only**. The key insight (from in-game
diagnosis): under bodycam the **render camera** — what `world2ui` and the
screen-center pick use, and what `device().cam_dir` returns — is a *swayed
override* of the actor's true gameplay camera. The weapon barrel pick
(`PP.defs.dir`) is the cosmetic swaying weapon-model direction, ~40° off view and
useless as an aim source (confirmed: it projects off-screen while aiming at an
on-screen target). The real aim is the actor's **first-eye camera**
(`CActor::cam_FirstEye()`), which the render camera is derived from —
`HudItem::Ray()` itself remaps the pick through `cam_FirstEye()` for this reason.

`ii_identify.script` gets it through an optional engine binding it probes at
runtime:

```
bodycam.get_fire_ray() -> {
  valid=bool,
  pos_x/y/z, dir_x/y/z,          -- PRIMARY: first-eye (gameplay aim) ray, unit dir
  bar_pos_x/y/z, bar_dir_x/y/z   -- diagnostic: cosmetic weapon-barrel ray
}
```

`freeaim_ray()` reads the primary (eye) ray; `weapon_aim_ui()` projects a point
`pos + dir * FREEAIM_PROJECT_DIST` (100 m) through `world2ui` — i.e. where the
gameplay aim lands on the *render* screen, which is the reticle position — and
`aim_center()` feeds it to `find_nearest_in_fov`. The whole path is guarded by
`rawget(_G,"bodycam")` and stays inert (falls back to screen center) until the
binding exists — safe on every engine.

**The binding does not ship with the stock bodycam engine and must be compiled
in.** Implemented in `src/xrGame/bodycam_script.cpp` (added to the `bodycam`
luabind module) as a pure, side-effect-free read of `actor->cam_FirstEye()`'s
`vPosition`/`vDirection` for the primary ray, plus the main-hand weapon's
`GetPick().defs` for the diagnostic barrel ray. Both dirs unit-length;
`valid=false` when there is no controlled actor.

Verify with `debug_log` on: the `[ii] aim(eye) ... ui=(x,y)` line should show an
on-screen coordinate that tracks the target as you free-aim, while `aim(barrel)`
is the off-screen cosmetic one.

## 11. Redaction (dead-body head effect, engine)

The **Bodycam** style (`ui_style = 3`, §1) and **`auto_identify`** are pure Lua
and work on any engine build. **Redaction** needs the custom bodycam exe. It is
**fully decoupled from identification** — its own subsystem, no tag/box/identify
involvement:

- **`redact_dead`** (toggle) — draw an effect over **every visible dead body in
  range**, no identify needed, persistent while visible, any UI style.
- **`redact_style`** (list) — `glitch` / `pixelate` / `black` (§ shader below).
- **`redact_area`** (list) — `head` (head/face box) or `body` (full-body box,
  centred `BODY_CENTER_LIFT` above the origin with body-sized extents). `redact_box_for`
  dispatches; both use the same `box_extents` projection with different metres.
- **`redact_strength`** — master intensity.
- **`redact_padding`** — extra margin around the region as a fraction of its size
  (`add_glitch_box` expands `hw/hh` by `1 + redact_padding`), distance-independent.
  The bodycam outline has the equivalent **`box_padding`** applied in `render`.

**Behavior.** `feed_glitch` runs every frame: when `redact_dead` is on it builds a
list of head boxes for the dead-in-range bodies (`update_corpse_membership`
throttles a `level.iterate_nearest` + alive-check sweep — **no LOS check**: the
shader's depth mask handles occlusion per-pixel, so gating on `db.actor:see` was
redundant and caused a pop-in delay from its grace window; ids are cached and the
head boxes re-projected every frame so they track the settling ragdoll) and
submits them in one atomic batch. Cleared when nothing qualifies, a
PiP scope is up, or the mod is disabled. Up to `GLITCH_MAX` (16) corpses at once.
(Identification's own dead handling is unchanged: a tag is dropped the instant its
target dies, `render`'s `remove = not alive`.)

**Hiding tags out of sight** (`hide_unseen`, default on, all styles): `render`
gates each active tag on `tag_visible(obj)` (a cheap cached `db.actor:see`) so an
occluded/off-screen target's tag is hidden instead of floating on the wall until
its timer expires; the `tracked` entry persists, so it reappears on re-sight.

`hide_unseen` uses `tag_visible` = `db.actor:see` **AND** `has_clear_ray` (a
fresh geometric static-ray) — `see` alone lags behind cover via its grace window,
so the ray gives the near-instant drop; a `HIDE_GRACE_MS` (150) debounce rides
out a one-frame ray flicker. **Full-body box** (`body_box_for`, used by both the
bodycam outline and redaction) is the screen-space bounding box of the projected
ragdoll bones (`BODY_BOX_BONES`) — so it tracks the physics ragdoll, unlike
`obj:position()` which stays at the last-alive spot; falls back to a vertical
origin span for non-bip01 rigs. Bodycam outline thickness is `box_thickness` (px,
fixed not distance-scaled), drawn with butted (non-overlapping) corners and
UI_KX-corrected vertical edges (`draw_head_box`).

**Actor-death teardown**: `teardown_ui()` hides all tag slots, clears `tracked`,
drops cached corpses, and clears the engine redaction. Driven two ways: an
`actor_on_before_death` callback fires it at the **moment of death** (the death
screen can freeze `actor_on_update` with the last frame's tags still drawn, so
the poll alone leaves them on the death screen), plus `actor_on_update` polls
`db.actor:alive()` as a backstop. Idempotent.

**Lua → engine contract** (guarded by `rawget(_G,"bodycam")`, inert on a stock
exe — the box still shows, just no distortion). Multi-rect, SVP-marker style:

```
bodycam.glitch_begin()                 -- start a frame's list
bodycam.glitch_add(x0, y0, x1, y1)     -- one head box, NORMALISED [0,1], top-left origin
bodycam.glitch_commit(intensity)       -- publish atomically (intensity 0 / empty list clears)
-- legacy single-rect wrappers kept: set_glitch_rect(...), clear_glitch()
```

`glitch_submit()` converts each box's 1024×768 virtual-space centre/extents to
`[0,1]` (divide by 1024/768, since that virtual space maps across the whole
screen); `intensity` = `redact_strength`.

**Effect variant** (`redact_style`, MCM list → engine mode via `bodycam.glitch_set_mode`,
a separate binding so older exes degrade to glitch): `0` glitch, `1` pixelate
(mosaic censor), `2` black box. Passed to the shader in `glitch_count.y`. (The
engine binding names stay `glitch_*` — internal plumbing, unchanged by the
mod-facing "redaction" rename.)

**Depth mask (never over the viewmodel)**: each box also carries its **view-space
depth** (`view_depth` in Lua = `(headPos − cam_pos)·cam_dir`, matching the engine's
`s_position.z`), threaded through `glitch_add(…,depth)` → `g_ii_glitch_depths[]` →
`set_ca("glitch_depths")`. The shader samples the scene depth (`s_position`,
`r2_RT_P`, bound by the blender) and **skips any pixel nearer than
`GLITCH_DEPTH_FRAC`×box-depth** (0.55) — a *relative* cutoff, not a fixed metric
margin: the box depth is the body CENTRE and its front-facing surfaces sit some
way in front of it (worse at an angle / full-body), so a fixed margin wrongly
excluded them and the body drew over the effect; relative-to-distance the body's
spread is small while the viewmodel is dramatically nearer, so this keeps the
whole body at any range/angle. So the gun/hands (in the g-buffer before combine
via `r_dsgraph_render_hud`) and any foreground geometry are excluded. A `continue`
(not bail) lets an overlapping box at a different depth still win. depth `0` = no
test (the back-compat single-rect wrapper).

**Shader** (ships as gamedata, this repo): `gamedata/shaders/r3/ii_glitch.ps` —
loaded at runtime by filename, DX11 path (`getShaderPath()` returns `"r3\\"`).
Samples the scene RT via the shared `s_image`/`smp_base`; **loops** the rect array
and, inside the first box a pixel hits (and passing the depth mask), applies the
mode's effect (glitch = banded tear + chromatic aberration + dropout +
scanline/noise; pixelate = quantise box UV to cells and resample; black = solid),
feathered at the edges, scene untouched elsewhere. Reads `float4 glitch_params (intensity,time,…)`, `float4 glitch_count
(.x = n, .y = mode)`, and `float4 glitch_rects[16]` set from C++ (rect array via
`set_ca`).

**Engine side (custom exe — staged, applied against the fork).** Modeled on the
fork's SVP `draw_scope` region-pass, itself a variant of the stock
`phase_fakescope` (`rendertarget_phase_nightvision.cpp`) + its `CBlender_fakescope`
(`blender_nightvision.cpp`, binds scene RT `r2_RT_generic0` → `s_image`):
1. `CBlender_glitch` binding `s_image` + selecting `ii_glitch.ps`; `ref_shader
   s_glitch` created in `r4_rendertarget.cpp` (`s_glitch.create(b_glitch,
   "r3\\ii_glitch")`).
2. `CRenderTarget::phase_glitch()` — bind `dx10_msaa ? rt_Generic : rt_Color`,
   draw the **fullscreen** `g_combine` quad, `set_c("glitch_rect"/"glitch_params",
   …)`, then `CopyResource` back into `rt_Generic_0`. **No scissor**: the pass is
   fullscreen and the region restriction lives in `ii_glitch.ps` (it returns the
   scene untouched outside `glitch_rect`), because `CopyResource` copies the whole
   RT back — a scissored draw would leave the area outside the box stale and
   corrupt the scene on copy-back. Inject in `r4_rendertarget_phase_combine.cpp`
   **after SMAA and TAA** (`phase_ssfx_taa`), immediately before the final
   `combine_2` pass, gated on `g_ii_glitch_active && !svp_pass_now`. Placement is
   load-bearing: running it *before* TAA (with the nightvision/fakescope FX) let
   TAA's temporal history rectification clamp the churning glitch out as an
   artifact (a stable overlay like fakescope survives, a per-frame glitch does
   not). After TAA, `rt_Generic_0` holds the finished post-AA scene that
   `combine_2` samples (`s_image = r2_RT_generic0`, `blender_combine.cpp`), so the
   distortion survives straight to screen.
3. Shared state as `ENGINE_API` globals in `xrEngine` (`xr_ioc_cmd.cpp`):
   `g_glitch_rect` (Fvector4, normalised), `g_glitch_intensity`,
   `g_glitch_active`; `bodycam_script.cpp` writes them, the R4 renderer `extern`s
   and reads them (same cross-module channel as `ps_r2_sun_shafts_min`).
4. `bodycam.set_glitch_rect`/`clear_glitch` added to `Bodycam::script_register`'s
   `module(L,"bodycam")[…]`; that `script_register(L)` is called from
   `script_engine_export.cpp`. New `.cpp` files → `xrGame.vcxproj` /
   `xrRender_R4.vcxproj`; game exe target is `AnomalyDX11` (`xrEngine.vcxproj`).
   `set_glitch_rect` stores the rect + sets `g_glitch_active=true`; renderer
   multiplies the `[0,1]` rect by `Device.dwWidth/dwHeight` for the scissor and
   passes the `[0,1]` rect straight to the shader.

Engine changes **applied** to the fork (branch `freeaim-identify-binding`), 7
files + the shader: `xr_ioc_cmd.cpp` (globals), `bodycam_script.cpp` (binding),
`blender_nightvision.{h,cpp}` (`CBlender_ii_glitch`), `r4_rendertarget.{h,cpp}`
(member/create/delete), `r4_rendertarget_phase_combine.cpp` (`phase_glitch` +
call). Needs an `AnomalyDX11` rebuild (MSBuild). Step-by-step notes:
`docs/engine-glitch-patch.md`.

## 12. In-scope (SVP/PiP) identification markers (engine)

The mod's `svp_ui_markers_begin/add/commit` + `is_svp_active` calls (gated by
`PIP_AVAILABLE`, a `rawget` existence check) draw identification markers **inside a
PiP scope**. These bindings were written against a PiP engine and **did not exist
in the bodycam fork** — only `is_svp_active` — so `PIP_AVAILABLE` was `false` and
the whole path was inert until Phase 1 built them.

**Phase 1 (engine, validated in-game):** a Lua→shared-buffer→render-pass→shader
pipeline (same shape as the redaction glitch). `svp_ui_markers_*` (registered in
`console_registrator_script.cpp` next to `is_svp_active`) stage a list of
WORLD-space markers into `g_ii_svp_markers[16×12]` (12 floats: world xyz, fill
rgba, radius, ring rgb, scanning). `CRenderTarget::phase_svp_markers` projects each
through the **SVP camera** (`Device.matrices[1]`, `mul(mProject,mView)` + clip
divide — the same recipe/source `svp_project_world_point_to_lens` and
`phase_svp_capture` use) and draws a small alpha sprite per marker.

Two placement facts were load-bearing (both cost a bringup cycle): the draw must
go into **`rt_Generic_0`** (the RT `phase_svp_capture` copies into `rt_secondVP`
for the lens to sample — not `rt_Color`/`rt_Generic`), and it must be injected at
the **top of `phase_svp_capture`** (svp_optics.cpp), not the `phase_combine` tail,
because `matrices[1]` is only the live scope camera at capture time. Viewport is
the SVP target's `Width`/`Height`. Shader `gamedata/shaders/r3/ii_svp_marker.ps`
(faction disc + relation ring + scanning arc; no in-scope text — infeasible in the
pass). Debug: console `r__ii_svp_marker_debug 1`. **No Lua changes** — the mod's
existing code drives it. Phase 2 (richer bracket/sign) not yet built.

**In-scope redaction** (same commit): the dead-body redaction glitch also runs in
the scope. `bodycam.glitch_add` gained WORLD box args (`wcx,wcy,wcz,whw,whh`,
stored in `g_ii_glitch_world[16×6]`); `phase_svp_glitch` (called in
`phase_svp_capture`, before the markers) reprojects each world box's 4
camera-facing corners through the SVP camera to a scope-normalised rect and reuses
`ii_glitch.ps` **unchanged** (depth `0` = no viewmodel mask in-scope). Lua-side
`head_box_for`/`body_box_for` now also return the box's world centre + world
half-extents (`body_box_for` accumulates a world AABB of the bones, so the in-scope
box tracks the ragdoll too), and `feed_glitch` no longer bails when scoped — the
engine draws the main-camera rects in the main pass and the world boxes in the SVP
pass; the lens only samples the SVP output, so there's no double-draw. Relies on
`SetActive` remapping `r2_RT_generic0`/`r2_RT_P` to the SVP RTs so the shader
samples the scope scene.

## 13. Known repo drift (flagged during analysis)

- **`README.md`** — verify its optional-component list matches the two components
  currently in `ModuleConfig.xml` (FactionID Neutralized, Perception Skill
  Integration).
