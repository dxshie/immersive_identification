# Immersive Identification — Technical Specification

> **Version:** 2.55.1 &nbsp;•&nbsp; **Engine:** X-Ray / xray-monolith (S.T.A.L.K.E.R. Anomaly / GAMMA), Lua 5.1
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

Four visual styles:

- **Card** (`ui_style = 1`): dark plate + faction icon + text lines + a leader
  line connecting to a colored dot on the target's chest.
- **Minimal** (`ui_style = 2`): just a faction-colored dot plus a relation glyph
  (`-` enemy / `+` friend / `o` neutral). With `mini_dist_scale` on, the dot
  scales with distance (near = bigger, far = smaller) instead of a flat size.
- **Simple 2** (`ui_style = 4`): a compact over-the-head cluster — a
  faction-colored circle (`ii_dot`) and a relation-colored triangle (`ii_tri`,
  pointing at relation) side by side, with a thin rank-colored bar above them
  (`rank_color`, novice grey → legend gold). Distance-scaled and anchored above
  the head like the PiP marker (`draw_slot`'s `ui_style == 4` branch).
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
    ii_identify.script          Core runtime (~4400 lines): logic + UI
    ii_mcm.script               MCM settings-menu definition (~207 lines)
  configs/
    text/eng/st_ii_texts.xml    String table (windows-1251)
    ui/ii_tags.xml              CUIStatic widget templates (card/minimal/bodycam/simple2/debug)
    ui/textures_descr/ii_textures.xml   Texture id -> file registration
    presets/                    includes.ltx + presets_ii.ltx (MCM preset values)
  textures/ui/*.dds             ii_white, ii_dot, ii_node, ii_spinner, ii_shadow, ii_tri
  shaders/r3/*.ps               bodycam redaction / svp-marker / overlay (custom exe)
fomod/
  info.xml                      Name/Author/Version 2.55.1/Website
  ModuleConfig.xml              Installer: base + 2 optional components
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

`on_game_start()` (4398-4414) is the sole bootstrap:

1. `read_config()` — load MCM/defaults (4399)
2. `install_key_hook()` — wrap `level_input.on_key_press` (4400)
3. Register the multi-subscriber callbacks (4401-4413): `actor_on_update`,
   `actor_on_before_death`, `on_option_change`, `save_state`, `load_state`, and
   `actor_on_weapon_zoom_in`/`actor_on_weapon_zoom_out` (the latter two are
   anonymous one-liners that set/clear `_ads.zoomed`, the ADS flag — kept anonymous
   so they add no top-level locals against Lua 5.1's 200-per-chunk limit).

- **Key hook** (`install_key_hook`, 2487): monkey-patches
  `level_input.on_key_press`, saving the previous handler and chaining to it via
  `pcall` so it **cooperates** with other mods rather than seizing the single
  native slot. On a matching DIK + modifier (and `not disabled`) it calls
  `try_identify()`.
- **Per-frame driver** (`actor_on_update`, 4323-4355): always runs
  `update_fov_baseline()`; polls actor death → `teardown_ui()`; then when enabled
  runs `ensure_tags()`, `update_binocular_scan()`, `update_auto_identify()`,
  `update_ads_range_cull()`, `update_redact_membership()`, `update_loot_xp()`, and
  `render()`.
- **Render surface** (`ensure_tags`, 3631): lazily creates the `IiTags`
  (`CUIScriptWnd`) dialog and registers it with `get_hud():AddDialogToRender()`.
  There is **no separate render callback** — drawing is done by repositioning
  persistent widgets each `actor_on_update` frame.
- **`on_option_change`** (4384-4386) re-reads config live when MCM changes.
- **`actor_on_before_death`** (4393-4396) tears the UI down at the moment of death
  (the death screen can freeze `actor_on_update` with the last frame's tags still
  drawn), backed up by the `actor_on_update` death poll.
- **`save_state` / `load_state`** (4369-4379) persist `xp_awarded`, `remembered`,
  `loot_xp_awarded`. Live reveal state (`tracked`) is intentionally not saved.
  Callbacks are declared `local` to avoid clobbering same-named globals in other
  scripts.

### 3.2 State machine

Central table `tracked`: `[obj_id] = { t0, col, fcol, sign, header, name, icon,
rank, rank_col, weap, scan_ms, max_dist, fade_dist, fade_ms, hold_ms }`, capped at
`MAX_TAGS = 12` (raised from 5). When full, the oldest entry (lowest `t0`) is
evicted before insert (in `identify_target`, 2097).

Each entry runs a **time-based state machine** keyed on
`elapsed = time_global() - t0`, evaluated every frame in `render()` (3969).
`total = scan_ms + fade_ms + hold_ms + fade_ms`:

| Phase | Condition | Visual |
|---|---|---|
| Scanning | `elapsed < scan_ms` | rotating spinner only, alpha 0 |
| Fade-in | `< scan_ms + fade_ms` | alpha ramps 0 → 1 |
| Hold | `< scan_ms + fade_ms + hold_ms` | full card, alpha 1 |
| Fade-out | else | alpha 1 → 0 |
| Removed | `elapsed > total`, or object gone/dead | — |

**Snapshot-at-identify:** all timing/range params are frozen into the `tracked`
entry at identify time (`identify_target`, 2097) and read from the entry during
render, so live MCM edits or lowering binoculars mid-reveal never retroactively
distort an in-progress card.

**Re-identify while tracked** (`identify_target`): a **manual** keypress restarts
the reveal by resetting `t0` and refreshing every snapshot, so the familiarity
discount (2nd+ identify) takes effect immediately. An **auto** re-touch
(`auto_mode = true`, from the steady/dwell triggers) does **not** restart a
target that is already scanning/revealed — it only refreshes the hold window —
so ADS combat micro-adjustment can't re-scan an already-identified target (the
"double identification" flicker, §3.5b).

### 3.3 Target selection

`get_target_obj(max_dist, allow_fov)` (1465) — a cascade:

0. Free-aim direct hit (only when `freeaim_assist` is on): `freeaim_target` raycasts
   along the true aim ray, tried **first** so a real aim-ray hit wins over the swayed
   render-camera trace below. Independent of `allow_fov`.
1. Weapon-aligned trace: `level.get_target_obj(level.ETraceTarget.Weapon)`
2. Camera trace fallback: `level.get_target_obj()`
3. FOV fallback: `find_nearest_in_fov(max_dist)` — **only if `allow_fov`**.
   `try_identify` passes `allow_fov`, which is `fov_assist_binoc` while looking
   through raised binoculars and `fov_assist` otherwise. With it off, identification
   is direct-hit only (tiers 0–2).

A direct hit that is **already mid-identification** doesn't just restart itself: the
FOV fallback is tried first (it prefers any *other* eligible target over one already
tracked), and the busy direct hit is only returned if nothing else qualifies.

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

`find_nearest_in_fov` (1291) iterates `level.iterate_nearest`; a candidate must be
non-actor, `IsStalker` or `IsMonster`, alive, have a non-empty
`character_community`, and (if `require_los`) pass LOS. It selects the candidate
**nearest to the aim point** within the assist tolerance, not nearest in world
space. Already-tracked targets are held as a runner-up and only returned if
nothing else qualifies.

**The assist is angular, not a screen ring** (the fix for PiP scopes). Instead of
measuring screen distance to a projected aim point, it measures the **angle from
the true aim ray** to the target:

- `aim_ray_world()` (1701) returns the fire ray `{origin, unit dir}` — the weapon
  **barrel** ray under ADS, the first-eye ray otherwise (both from
  `bodycam.get_fire_ray()`), falling back to `device().cam_pos/cam_dir` on a stock
  engine. This is where the scope/gun actually points, not the swayed render camera.
- `aim_angle_to_body(obj)` (1748) returns the smallest angle from that ray to any
  sampled `BODY_BONES` point (head/torso/pelvis/limbs — so aiming anywhere on the
  entity counts), via the module-level `ray_point_angle` helper; a vertical span at
  the origin backs up non-`bip01` rigs (monsters).
- `aim_cone_rad()` (1690) is the tolerance as a **constant real angle**:
  `(fov_radius / 768) × baseline_fov`. A candidate matches when
  `aim_angle_to_body(obj) ≤ aim_cone_rad()`.

Because it's an angle from the aim ray, the assist is **magnification-invariant** (a
scope zooms the view, not the target's real angular size) and **sway-immune** (it
doesn't go through the swayed render camera). At 1× it matches the old screen ring,
so hip-fire feel is unchanged.

`aim_center()` / `weapon_aim_ui()` (903 / 874) — the old screen-space aim-point
projection — are now used **only by the debug visualiser** (`draw_debug`) and the
aim-debug dump, not by target selection.

### 3.4 Scan-time computation

`try_identify()` (2244) resolves the target and hands it to `identify_target`
(2097), which commits immediately; the visible delay `eff_scan_ms` is `SCAN_MS`
multiplied through a chain of factors (or skipped entirely when `instant_identify`
is on):

| Factor | Function | Range |
|---|---|---|
| Distance | `distance_scan_mult` (1788) | 1× point-blank → `dist_penalty_max` at cutoff |
| Rank | `rank_scan_mult` (1838) | 1× novice → `rank_penalty_max` legend |
| Night | `night_scan_mult` (1901) | 1× day → `night_penalty_max`, scaled by `darkness_factor` (1881), peaks around midnight |
| Binoculars / ADS | `scan_mult` from `boost_params` (2204) | flat multiplier while raised/aiming (if the matching `*_boost`) |
| Perception | `perception_scan_mult` (1932) | `1 − perception_scan_mult × level`, floored |
| Familiarity | `familiarity_scan_mult` | applied if `remembered[id]` |

Gating (`try_identify`): `enabled` + actor exists; if `require_binoculars`,
`is_binoc_active()` must be true; target exists, is not the actor, is alive, has a
community, and is within `eff_max_dist`.

### 3.5 Binoculars

- `is_binoc_held()` (1521): `active_item():section()` contains
  `BINOC_SECTION = "wpn_binoc_inv"`.
- `is_binoc_active()` (1571): additionally requires camera FOV to have dropped
  below `FOV_ZOOM_RATIO (0.7) × _fov_baseline`; the baseline self-calibrates each
  frame from the widest FOV seen while binoculars aren't held
  (`update_fov_baseline`, 1560).
- `binoc_boost` widens `eff_max_dist` / `eff_fade_dist` by `binoc_range_mult`
  (default **4.4**) and speeds the scan (`boost_params`, 2204). With
  `binoc_zoom_scaling` on, the range multiplier is further scaled by the
  binocular's magnification (like `ads_zoom_scaling`).
- **Steady auto-identify** (`update_binocular_scan`, 2445): when `binocular_mode` is
  active, tracks a "steady" camera direction against an anchor
  (`STEADY_MAX_D2 = 0.002`, ~2.6°); held steady for `steady_time` it fires a
  **sweep** (`sweep_identify_in_fov`, if `fov_assist_binoc`) or a direct
  `try_identify(true)` (if not), throttled by `STEADY_SWEEP_MS` so it keeps
  re-sweeping while held. ADS uses a separate dwell trigger (§3.5b).

### 3.5b Aim Down Sight (ADS)

Mirrors the binocular boost for regular weapons. `is_ads_active()` (1590) detects
aiming down sight on **any exe**, in priority order:

1. **PRIMARY: `_ads.zoomed`** — a flag driven by the stock
   `actor_on_weapon_zoom_in`/`_out` callbacks (registered in `on_game_start`). This
   works on any engine and catches **1× optics** that change no FOV — the case the
   heuristics below can't see. Self-heals a stuck flag: if it's set but the actor has
   no active item in hand (holstered/switched), it resets and reports hipfire.
2. `bodycam.get_state().ads` — only trusted while the bodycam logic is **active**
   (`st.active`); when disabled the field is stale/false.
3. A live PiP scope (`is_svp_active()`) — a scope narrows the *second* viewport, not
   the main FOV, so the heuristic below can't see it.
4. FOV-zoom heuristic: `device().fov < _fov_baseline × ADS_ZOOM_RATIO (0.85)`.

Binoculars are excluded (`is_binoc_held` checked first) so ADS and binocular boosts
never stack. `boost_params()` (2204) returns
`(binoc, ads, boosted, eff_max_dist, eff_fade_dist, scan_mult)` — binoc takes
priority, then ADS, each carrying its own `*_scan_mult` / `*_range_mult` from its
MCM section; `identify_target` applies the returned `scan_mult`. Its own MCM
section: `ads_mode`, `ads_hold_time`, `ads_boost`, `ads_scan_mult`,
`ads_range_mult`, `ads_zoom_scaling`, `ads_hide_main`.

**ADS auto-identify is dwell-on-target** (`update_ads_dwell`, 2394), distinct from
the binocular *steadiness* trigger: it requires a valid target to be **continuously
present under the aim** — directly, or inside the FOV-assist cone when `fov_assist`
is on — for `ads_hold_time` seconds, then auto-identifies (and keeps identifying,
throttled, while a target stays there). Holding still on empty air does nothing; you
*can* track a moving target. `fov_assist` on → `sweep_identify_in_fov` (all targets
in the cone); off → `try_identify(true)` (just the one under the aim). The presence
raycast is throttled to 100 ms; the dwell timer uses `time_global` so it stays exact.

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
the world box extents in `redaction_submit` so the engine's SVP redaction pass skips
them (the main-view redaction is unaffected).

**Suppress main-view drawing**: `suppress_main = (ads_hide_main and is_ads_active())
or (pip_hide_main and pip_scope)` hides ALL main-view drawing — the HUD tags (adds
to the `pip_active or suppress_main` hide-slots-and-return) and the main-pass
redaction (`redaction_submit(…, main_off)` submits each box's main-camera rect
off-screen — outside `[0,1]`, so the main redaction shader finds no pixels — while the
WORLD box still feeds the in-scope pass). The in-scope UI is unaffected, so with a
PiP scope up you get in-scope-only rendering. `pip_scope` is the physical scope
state (independent of `pip_markers`), so this also covers `pip_markers`-off.

### 3.6 UI rendering

`IiTags : CUIScriptWnd` (`__init` 2529), rect 1024×768, parses `ii_tags.xml` via
`CScriptXmlInit`. `InitControls` (2534) builds `MAX_TAGS` slots of widgets in draw
order (shadow → line → plate → accent → icon → text → node/glow → spinner →
bodycam box edges → Simple 2 circle/triangle/bar), plus the debug dot/text pool.

- **World-to-screen:** `anchor_pos(obj)` (610) picks the first of `ANCHOR_BONES`
  (`bip01_head`, `bip01_spine2/1`, `bip01_spine`) within 3m and lifts by
  `ANCHOR_LIFT = 0.12`; monsters fall back to `position().y + 1.3`. `project_world`
  (623) calls `game/level.world2ui`, rejecting `x < -9000` (off-screen/behind).
- **`draw_slot`** (3147) branches: scanning spinner only → **bodycam** (head-outline
  box, `ui_style==3`) → **Simple 2** (circle+triangle+rank bar, `ui_style==4`) →
  minimal (node+glow+glyph, `ui_style==2`) → mini fallback below `mini_scale_cutoff`
  (node+glow) → full card (measured text, plate, accent, icon, shadowed text lines,
  node/glow, and a leader line rotated via `atan2`/`SetHeading` from node to the
  card's nearest bottom corner). The bodycam box's centre/extents (`box_cx/cy/hw/hh`)
  are precomputed per target in `render` (via `area_box_for`) since `draw_slot` has
  no world access.
- **Distance scaling / offsets:** the Minimal dot (`mini_dist_scale_factor`, 3025,
  when `mini_dist_scale` on) and the Simple 2 cluster scale with distance and are
  pulled toward the head as the target recedes; `ui_offset_x` / `ui_offset_y` nudge
  every on-screen element in virtual px.
- **Aspect correction** `UI_KX` (assigned 375): `(h/w)/(768/1024)`; the X of any
  KX-distorted static (node, glow, line, Simple 2 shapes) is pre-corrected so circles
  stay round and angles stay true under the engine's anisotropic virtual→screen
  stretch. The spinner is deliberately kept square (rotation doesn't commute with
  non-uniform scale).
- **Overlap avoidance** (`render` 2nd pass, ~4222): a card whose anchor is within
  `STACK_DIST_X=140` / `STACK_DIST_Y=90` of an earlier card is pushed
  `stack × STACK_STEP (58)` px higher.
- **Picture-in-Picture scope path** (in `render`, 3969): gated on `PIP_AVAILABLE`
  (soft existence check via `rawget` of `is_svp_active` / `svp_ui_markers_*`). When a
  scope is raised it submits in-scope world markers and hides the normal HUD slots so
  a mis-projected main-camera card doesn't clash with the scope view.

### 3.7 Rewards / familiarity

- First identify of a target awards `perception_xp` once (`xp_awarded` gate) and
  sets `remembered[id]` (in `identify_target`, 2097).
- `update_loot_xp` (2064) awards `perception_loot_xp` the first time you loot a
  corpse you had already identified, detected by polling `get_talking_npc()` for a
  set→cleared transition (`loot_xp_awarded` gate).
- `award_perception_xp` (2012) writes `haru_skills.skills_levels.perception
  .experience` directly (deliberately not `increase_skill`, which would throw on a
  non-base skill).

### 3.8 Notable functions

`read_config` (353) • `active_dik` (381) • `modifiers_ok` (399) •
`faction_label/color` (421/436) • `display_name` (443) • `rank_color/label`
(477/482) • `held_weapon_label` (533) • `relation_color/sign` (578/596) •
`anchor_pos` (610) • `project_world` (623) • `screen_box` (691) • `has_los` (1230) •
`find_nearest_in_fov` (1291) • `get_target_obj` (1465) • `is_binoc_active` (1571) •
`is_ads_active` (1590) • `scope_magnification` (1647) • `aim_cone_rad` (1690) •
`aim_ray_world` (1701) • `aim_angle_to_body` (1748) • `distance_scan_mult` (1788) •
`rank_scan_mult` (1838) • `darkness_factor` (1881) • `perception_scan_mult` (1932) •
`perception_hint_stats` (1968, exposed as a global for the Skill System tooltip) •
`update_loot_xp` (2064) • `identify_target` (2097) • `boost_params` (2204) •
`try_identify` (2244) • `update_auto_identify` (2296) • `sweep_identify_in_fov`
(2359) • `update_ads_dwell` (2394) • `update_binocular_scan` (2445) •
`install_key_hook` (2487) • `IiTags:InitControls` (2534) • `IiTags:draw_debug`
(2740) • `draw_head_box` (2954) • `IiTags:draw_slot` (3147) • `ensure_tags` (3631) •
`head_box_for` (3687) • `body_box_for` (3749) • `face_box_for` (3846) •
`update_redact_membership` (3876) • `feed_redaction` (3935) • `render` (3969) •
`teardown_ui` (4273) • `update_ads_range_cull` (4303) • `actor_on_update` (4323) •
`on_game_start` (4398).

---

## 4. Configuration (MCM — `ii_mcm.script`)

MCM auto-discovers `on_mcm_load` only in files ending `mcm.script`, so the menu
lives here while logic stays in `ii_identify.script`. **Single source of truth:**
defaults, the modifier dropdown, and the UI-style dropdown are read from
`ii_identify.DEFAULTS` / `MODIFIER_LIST` / `UI_STYLE_LIST` (11-25). The key-bind
default is resolved here (not in `DEFAULTS`) because `DIK_keys` isn't populated
when `ii_identify.script` is first parsed (27-31).

**Presets:** the General leaf page carries a `presets = { "ii_card", "ii_minimal",
"ii_bodycam", "ii_immersive" }` list, which makes MCM show a preset dropdown (it
applies across all pages, not just General). Names resolve from `ui_mcm_prst_<id>`
strings; **values live in LTX**, not Lua — MCM reads `configs/presets/includes.ltx`
(which we ship with a wildcard `#include "presets_*.ltx"` so other mods coexist) →
`presets_ii.ltx`, whose `[<preset_id>]` sections key options by their storage path
(`ii/<page>/<id>` — see the multi-page note below; values by type: check→bool,
track/list→number). A preset only overrides the options it lists. Adding an option
to a preset = one LTX line; no code change.

**Tree:** root node `id="ii"` (no `sh`) → **one leaf page (`sh=true`) per section**,
each rendering as its own tab (tab label = `ui_mcm_menu_<page_id>`): **general**,
**uistyle**, **targeting**, **binoc**, **ads**, **pip**, **faceredact**, **scantime**
(the distance/rank/night/familiarity/perception modifier sub-headers), **debug**, and
**colors** (the per-faction/rank/relation RGB overrides, generated from
`ii_identify.COLOR_DEFS`). Because an option's MCM storage path is
`ii/<page>/<option_id>`, options are NOT all under `ii/main/*` — `read_config` resolves
each key by trying every page in `MCM_PAGES` (first non-nil wins), and the preset LTX
paths use the per-page ids. Three MCM traps encoded in comments:
the top node must **not** carry `sh` (only the leaf page does); an option's
**`hint` is the BARE base id** (`"ii_<id>"`) — MCM resolves its caption from
`ui_mcm_<hint>` and its **hover tooltip** from `ui_mcm_<hint>_desc`, so passing a
`_desc`-suffixed hint mis-renders the label and kills the tooltip; and `text` is
only read for slide headers, not option captions. The `opt_check/opt_track/
opt_list` helpers set `hint = "ii_" .. id` mechanically.

### Setting inventory

Listed in MCM display order (`ii_mcm.script`); ranges are `(min, max, step, prec)`.

| id | type | default | range | controls |
|---|---|---|---|---|
| **General** | | | | |
| `enabled` | check | true | — | master on/off |
| `key_dik` | key_bind | `DIK_X` | — | identify key |
| `modifier_index` | list | None | None/Ctrl/Shift/Alt | required held modifier |
| `instant_identify` | check | false | — | skip the scan wait — reveal immediately |
| `scan_time` | track | 0.35 | 0, 2, 0.05, 2 | base scan pulse (s) |
| `fade_time` | track | 0.45 | 0.1, 2, 0.05, 2 | fade in/out (s) |
| `hold_time` | track | 4.0 | 1, 15, 0.5, 1 | full-visible hold (s) |
| `hide_unseen` | check | true | — | hide a tag while its target is out of sight |
| `max_dist` | track | 50 | 10, 500, 10 | max identify range (m) |
| `fade_dist` | track | 40 | 5, 500, 10 | distance where card fades (m) |
| **UI Style** | | | | |
| `ui_style` | list | Card | Card/Minimal/Bodycam/Simple 2 | which visual style |
| `box_area` | list | Head | Head/Body | bodycam outline rectangle region |
| `box_color_source` | list | faction | faction/relation | bodycam box colour source |
| `box_thickness` | track | 2 | 1, 6, 0.5, 1 | bodycam outline edge thickness (px) |
| `box_padding` | track | 0.2 | 0, 1, 0.05, 2 | bodycam outline margin (fraction) |
| `box_opacity` | track | 1.0 | 0.1, 1, 0.05, 2 | bodycam outline opacity |
| `show_name` | check | true | — | show name line (card + bodycam) |
| `show_faction` | check | true | — | show faction line (card + bodycam) |
| `show_weapon` | check | true | — | show weapon+caliber line (card + bodycam) |
| `color_by_relation` | check | true | — | tint by relation vs flat neutral |
| `card_scale` | track | 1.0 | 0.5, 2, 0.05, 2 | flat card size multiplier |
| `mini_scale_cutoff` | track | 0.4 | 0.1, 1, 0.05, 2 | below this scale → dot only |
| `mini_dist_scale` | check | true | — | Minimal dot: scale with distance |
| `ui_offset_x` | track | 0 | -200, 200, 5 | horizontal nudge for on-screen UI (px) |
| `ui_offset_y` | track | 0 | -200, 200, 5 | vertical nudge for on-screen UI (px) |
| **Targeting** | | | | |
| `fov_assist` | check | true | — | master FOV target-assist; off = direct-hit aim only |
| `freeaim_assist` | check | false | — | bodycam/free-aim: aim from the weapon barrel ray |
| `fov_radius` | track | 90 | 0, 90, 5 | target-assist cone size (calibrated px; 0 = off) |
| `require_los` | check | true | — | require line of sight |
| `auto_identify` | check | false | — | continuously identify all visible in-range targets, no keypress (LOS always required) |
| **Binoculars** | | | | |
| `binocular_mode` | check | false | — | steady-aim auto-identify via binocs |
| `require_binoculars` | check | false | — | restrict identify to raised binocs |
| `steady_time` | track | 0.6 | 0.2, 3, 0.1, 1 | steady-aim hold time (s) |
| `fov_assist_binoc` | check | true | — | FOV assist while looking through raised binoculars |
| `binoc_boost` | check | true | — | binocs speed up + extend range |
| `binoc_scan_mult` | track | 0.4 | 0.1, 1, 0.05, 2 | scan-speed mult w/ binocs |
| `binoc_range_mult` | track | 4.4 | 1, 5, 0.1, 1 | max/fade distance mult w/ binocs |
| `binoc_zoom_scaling` | check | false | — | scale binoc range by binocular magnification |
| **Aim Down Sight (ADS)** | | | | |
| `ads_mode` | check | false | — | dwell-on-target auto-identify while ADS |
| `ads_hold_time` | track | 0.6 | 0.2, 3, 0.1, 1 | dwell time on target before auto-ID (s) |
| `ads_boost` | check | true | — | ADS speeds up + extends range |
| `ads_scan_mult` | track | 0.6 | 0.1, 1, 0.05, 2 | scan-speed mult while ADS |
| `ads_range_mult` | track | 1.6 | 1, 5, 0.1, 1 | max/fade distance mult while ADS (x1 base) |
| `ads_zoom_scaling` | check | true | — | scale ADS range by scope magnification |
| `ads_hide_main` | check | false | — | hide all main-view drawing while aiming down sight |
| **PiP Scope** | | | | |
| `pip_markers` | check | true | — | draw identification markers in a PiP scope |
| `pip_redact` | check | true | — | draw redaction in a PiP scope |
| `pip_hide_main` | check | false | — | hide all main-view drawing while a scope is up |
| **Face Redaction** | | | | |
| `redact_face` | check | false | — | redact the face of humanoids in range (alive or dead) |
| `redact_face_style` | list | pixelate | pixelate/black | face redaction distortion |
| `redact_face_padding` | track | 0.15 | 0, 1, 0.05, 2 | margin around the face box (fraction) |
| `redact_range` | track | 100 | 10, 300, 10 | redaction reach (m) |
| `redact_strength` | track | 1.0 | 0.1, 1, 0.05, 2 | redaction intensity |
| **Scan-time modifiers** | | | | |
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
| **Debug** | | | | |
| `debug_log` | check | false | — | write aim/trace diagnostics to a dedicated log file |
| `debug_draw` | check | false | — | on-screen target-assist visualiser |
| **Wearable Devices** (page `wdcompat`; only bites when the WD compat add-on is installed, §7.3) | | | | |
| `wd_require_kit` | check | true | — | block identification entirely unless the full scanner kit is worn/assembled |
| `wd_proc_t1/t2/t3` | track | 1.5 / 1.0 / 0.5 | 0.1, 5, 0.1, 1 | process-module tier base scan time (s) |
| `wd_scan_t1/t2/t3` | track | 10 / 20 / 30 | 5, 100, 5 | scanner tier identify range (m) |
| `wd_feat_faction/distance/relationship/rank/weapon` | track | 1/1/2/2/3 | 1, 3, 1 | process tier that unlocks each data feature |
| `wd_scanner_ads/mag/nonight` | track | 2/2/3 | 1, 3, 1 | scanner tier that unlocks scope-ADS / mag-boost / no-night |

The `wd_*` keys back the tier system's defaults and are exposed to the add-on via the
`ii_identify.get_wd_tier_cfg()` global (the add-on's driver can't read the local `C`).
See §7.3.

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
per frame), `tag_s2_circle` (12×12, ii_dot — Simple 2 faction circle),
`tag_s2_tri` (13×11, ii_tri — Simple 2 relation triangle), `tag_s2_bar` (28×3,
ii_white — Simple 2 rank bar), and the debug pool `dbg_dot` (ii_dot) +
`dbg_text`/`dbg_status` (letterica16). Text widgets (each with a `_sh` shadow twin):
`tag_head` (letterica16, faction), `tag_name` (letterica18, personal name),
`tag_rank` (letterica16, hidden for monsters), `tag_weap` (letterica16),
`tag_sign` (letterica18, centered relation glyph for Minimal style).

### 5.2 Textures (`ii_textures.xml` → `textures/ui/*.dds`)

Each registers the whole file as one region. `ii_white` (32×32 solid),
`ii_dot` (64×64 soft AA circle, glow/pulse), `ii_node` (64×64 white fill with a
**baked black outline ring** so the ring survives any tint), `ii_spinner`
(128×128 comet-tail ring), `ii_shadow` (64×64 feathered rounded box), `ii_tri`
(64×64 up-pointing triangle, shape in the alpha channel, tinted at runtime — Simple
2 relation marker). All ship white with the shape carried in alpha and are tinted at
runtime via `SetTextureColor`. Textures ship in-mod so the tag draws with zero
external dependency.

### 5.3 String table (`st_ii_texts.xml`, windows-1251)

MCM menu labels; a `ui_mcm_ii_<id>` label + `ui_mcm_ii_<id>_desc` hint pair per
setting; section titles; dropdown entry ids (`ii_main_<option>_lst_<label>`); and
16 faction display names `st_ii_faction_<community>` (Loner, Bandits, Duty,
Freedom, Clear Sky, Ecologists, Mercenaries, Military, Monolith, Renegades,
Zombified, Sin, Trader, Mutant, UNISG, Arena).

---

## 6. Installer & optional components (`fomod/`)

**info.xml:** Immersive Identification, **v2.55.1**, group Gameplay.

**ModuleConfig.xml** (ModConfig 5.0):

- **Required:** `gamedata → gamedata` (self-contained drop-in, no required
  choices).
- **One step** "Optional Components" → group "Compatibility" (`SelectAny`), three
  optional plugins (all unchecked by default):
  1. **Neutralize FactionID HUD** → installs `FactionID Neutralized/gamedata`.
  2. **Skill System: Perception** → installs `Perception Skill Integration/gamedata`.
  3. **st-wearable-devices Compatibility** → installs `WD Compatibility/gamedata` (§7.3).

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

### 7.3 st-wearable-devices Compatibility (`WD Compatibility/`)

Gates identification behind wearable scanner gear from the **st-wearable-devices**
(WD) mod, via a small **provider seam** in core: `ii_identify` calls the optional
global `ii_identify.tier_provider()` once per `actor_on_update` and snapshots the
result into `_tier`. Every override point reads `_tier`; when it's `nil` the mod
behaves exactly as normal, so core stays inert without this add-on. The provider
returns one of: `nil` (don't intervene), `{ active = false }` (installed but the kit
isn't assembled → identification **blocked** at the single `identify_target` choke
point), or `{ active = true, scan_base, max_dist, ignore_night, allow_ads, mag_boost,
feat = {...} }` (tier params drive identification). When active, the tier values
**replace** the matching MCM settings (scan-time chain, range, night penalty, ADS/mag
enablement, and the faction/distance/relationship/rank/weapon display gates); the rest
of the MCM (UI style, colours, key bind, …) is untouched.

**New items** (all placeholder art — see the component `README`):
- **Promin modules** — antenna, **OSD Scanner Module T1/T2/T3**, and process T1/T2/T3 —
  real WD Promin bay-modules, installed via WD's own system (item use menu / bracer
  customize screen), so they appear in the customize cells with their icons.
  `ii_wd_modules.register()` **repurposes WD's two functionally-empty bays** (drops WD's
  do-nothing `conn`/`side` `MODULES` entries) **and adds a fourth bay** so all four modules
  fit at once:
  - `conn` bay: the **antenna**.
  - `side` bay: a **process** tier.
  - `ii_osd` bay (added to `d_promin_config.BAYS`): an **OSD scanner** tier.
  - (`map` bay: WD's own navigation module.)

  The 4th bay requires a shipped **override of WD's `ui_wd_customize.xml`** (a 4th
  `module_open_4`/`module_restricted_4`/`cell_4`) — WD's customize screen builds one cell per
  `d_promin_config.BAYS` entry and ships XML for only three, so a 4th bay is otherwise a fatal
  `module_open_4 not found`. All install through `ii_wd_modules.install`, which evicts any
  module already in the target bay first (WD's `install_module` appends without checking).
  All three of our bays are made active on every Promin tier so the kit works on a tier-1
  Promin. WD persists the installed set; detection is
  `d_promin.has_module("ii_ant"/"ii_osd_tN"/"ii_proc_tN")`.
- **AR Scanner T1/T2/T3** — a **worn** bracer device (`d_ii_scanner.script`, mirroring WD's
  `d_vektor`/`d_bracer`: `wd_worn` + `wd_slots.register_device` + `wd_exo`), 3 tiers
  (range/ADS/mag/night). Shows identification on entities (the usual tags). Attaches **no
  worn model** (invisible — a placeholder mesh showed a duplicate bracer) and registers its
  own callbacks from `on_game_start` (this component isn't in WD's hardcoded `wd_boot` list,
  and `wd_core.start()` wires only once).

**Two INDEPENDENT channels** (separate bays, both installable at once):
- **AR** = antenna installed + a worn AR scanner + bracer worn + Promin worn & powered →
  identification on entities (the usual overlays).
- **OSD** = an OSD scanner module installed + a process module + Promin worn & powered
  (no antenna, no worn scanner, no bracer) → the Promin ident-page readout.

`osd_only` (core suppresses **all** on-entity identification UI — main tags *and* in-scope
markers, face redaction untouched) is set only in **pure OSD mode** (OSD ready and AR not).
With both channels' gear, entity overlays *and* the Promin readout show together. The Promin
ident page is gated on the OSD scanner module being installed.

**Driver** (`ii_wd_compat.script`): polls WD state — `d_ii_scanner.worn_tier()`,
`ii_wd_modules.process_tier()` / `osd_scanner_tier()` / `has_antenna()`, `d_bracer.is_worn()`,
`d_promin.is_worn()/is_powered()` — and the user's tier values via
`ii_identify.get_wd_tier_cfg()`, then builds the override table (cached, refreshed every
~250 ms). Identification runs if either channel is ready; the scanner tier used is the best
(max) of whichever are ready → `max_dist` + `allow_binoc` (T1) + `allow_ads` (T2) +
`mag_boost` (T2) + `ignore_night` (T3); process tier → `scan_base` + the display-feature
unlocks. **Binoculars** count under the tier system when the scanner unlocks them
(`allow_binoc`, T1 by default): raised binoculars extend the tier's identify range by
`binoc_range_mult` (`boost_params` tier branch), for both channels. All WD calls are `rawget`/`pcall`-guarded so the component is inert (returns `nil`)
when WD or II is absent, and never throws into core's per-frame path.

**Bootstrap gotcha** (fixed): `on_game_start` is auto-called by the engine for every
script, but `actor_on_first_update` is a callback that must be wired via
`RegisterScriptCallback` — an early version defined it as a bare global, so its body never
ran. All wiring now happens in `on_game_start`.

**Promin IDENTIFICATION tab**: installing the antenna adds a third Promin screen page
(`pages = {"ident"}` on the antenna module → WD's `get_available_pages` puts it in the
tab cycle). It mirrors the NAVIGATION page — reuses `d_promin_health_ui.build_chrome`
(bg `ii_wd_tab_bg_ident`) + `build_bio` to keep the frame + left biomonitor, and draws the
last-identified target in the **right panel** (the map's region, design rect
`572,85,425,450`): a **portrait** (`obj:character_icon()`) + name/faction/rank/position/
distance/weapon (locked fields `---`; monsters have no portrait) + a **scanning spinner**
(`ii_wd_spinner.dds`, frame-cycled) shown over the portrait while a scan is in progress
(driven by `ii_identify.get_scan_progress()`). The **IDENTIFICATION tab is a real baked tab**:
the strip (IDENTIFICATION / BIOMONITOR / NAVIGATION, active one highlighted) is baked into
the page background art — the ident page has its own `tablet_ui_main_ident.dds`, and WD's
biomonitor + navigation backgrounds (`tablet_ui_main.dds`, `tablet_ui_main_map.dds`) are
**overridden** so the third tab shows on every page (DXT5, matching WD's format). Data comes
from `ii_identify.get_last_identified()` (a persistent snapshot written at scan *completion*
in the render loop, respecting the tier feature gates, so the readout honours scan time). The Promin CRT
screen has **no font** (WD renders numbers as pre-baked digit textures), so this ships a
**monospace glyph atlas** (`ii_wd_font.dds` + a `textures_descr` mapping one id per ASCII
code) + a compositor (`ii_wd_text.script`) that draws strings by binding per-character
glyph textures onto slot widgets — the same mechanism as WD's clock. WD's page-builder
table is a file-local with no seam, so the page needs a **VFS override of
`d_promin_ui.script`** (verbatim copy + two `II-COMPAT` additions: the `ident` builder and
a second `ctx.init_ii` for our own node xml) — re-sync on a WD update.

**Untestable / placeholder** (flagged in the component `README`): the scanner is invisible
(no worn model — re-enable + tune the attach in `sync_attachment` for real art); the
scanner/module icons are generated placeholders; the IDENTIFICATION page's screen layout
(coordinates in the 1100×600 design space) and glyph sizing are best-guess and will likely
need in-game tuning. None affects the tier **logic**.

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

`freeaim_ray(source)` reads the ray — the weapon **barrel** ray (`bar_*`) under ADS,
the first-eye ray otherwise. The angular target-assist consumes it **directly**:
`aim_ray_world()` normalises it and `aim_angle_to_body()` measures the angle from it
to each candidate (§3.3), so there is no screen projection in the hot path any more.
(The old `weapon_aim_ui()` — projecting `pos + dir * FREEAIM_PROJECT_DIST` (100 m)
through `world2ui` to a reticle screen point — and `aim_center()` survive only as
the debug visualiser's aim marker.) The whole path is guarded by
`rawget(_G,"bodycam")` and stays inert (falls back to the render camera / screen
centre) until the binding exists — safe on every engine.

**The binding does not ship with the stock bodycam engine and must be compiled
in.** Implemented in `src/xrGame/bodycam_script.cpp` (added to the `bodycam`
luabind module) as a pure, side-effect-free read of `actor->cam_FirstEye()`'s
`vPosition`/`vDirection` for the primary ray, plus the main-hand weapon's
`GetPick().defs` for the diagnostic barrel ray. Both dirs unit-length;
`valid=false` when there is no controlled actor.

Verify with `debug_log` on: the `[ii] aim(eye) ... ui=(x,y)` line should show an
on-screen coordinate that tracks the target as you free-aim, while `aim(barrel)`
is the off-screen cosmetic one.

## 11. Face redaction (engine post-process)

The **Bodycam** style (`ui_style = 3`, §1) and **`auto_identify`** are pure Lua and
work on any engine build. **Face redaction** needs the custom bodycam exe. It is
**fully decoupled from identification** — its own subsystem, no tag/box/identify
involvement. (A wider *corpse* redaction — dead-body / full-body boxes with
`redact_dead`/`redact_area`/`redact_style`/`redact_padding` — existed in earlier
versions and was **removed**; only face redaction remains. The engine binding names
stay `redaction_*` — internal plumbing.)

- **`redact_face`** (toggle) — draw a distortion over the **face of every visible
  humanoid in range, alive or dead**, no identify needed, persistent while visible,
  any UI style.
- **`redact_face_style`** (list) — `pixelate` / `black` (§ shader below).
- **`redact_face_padding`** — extra margin around the face box as a fraction of its
  size (`add_redaction_box` expands `hw/hh` by `1 + padding`), distance-independent.
- **`redact_range`** (default 100 m) — the membership sweep uses this instead of the
  identify `max_dist`, since redaction is passive (no aiming) and should reach as far
  as a face is visible. A distant face still stops naturally once its box projects
  below ~1 px (`screen_box`).
- **`redact_strength`** — master intensity.

`face_box_for` (3846) builds the box: a tight head box, nudged forward along
`obj:direction()` so it sits over the face **front**, not the skull (humanoids only —
`head_center` is nil for monsters). **Front-only**: it NEGATES its depth as a shader
flag, so the shader uses a tight, front-biased band (`FACE_FRONT`/`FACE_BACK`) —
only the face front + sides, not the back of the head. (The engine passes the depth
through untouched, so no rebuild.)

One throttled sweep (`update_redact_membership`, 3876) builds `face_ids` (humanoid,
alive/dead) in range, gated on the toggle.

**Behavior.** `feed_redaction` (3935) runs every frame, builds the face box list
(`add_redaction_box(…, face_box_for, redact_face_padding)`), and submits in one
atomic batch — **no LOS check**: the shader's depth mask handles occlusion per-pixel
(gating on `db.actor:see` was redundant and caused a pop-in delay). Ids cached, boxes
re-projected every frame (tracks the settling ragdoll). Up to `REDACTION_MAX` (16)
boxes total.
(Identification's own dead handling is unchanged: a tag is dropped the instant its
target dies, `render`'s `remove = not alive`.)

**Hiding tags out of sight** (`hide_unseen`, default on, all styles): `render`
gates each active tag on `tag_visible(obj)` (a cheap cached `db.actor:see`) so an
occluded/off-screen target's tag is hidden instead of floating on the wall until
its timer expires; the `tracked` entry persists, so it reappears on re-sight.

`hide_unseen` uses `tag_visible` = `db.actor:see` **AND** `has_clear_ray` (a
fresh geometric static-ray) — `see` alone lags behind cover via its grace window,
so the ray gives the near-instant drop; a `HIDE_GRACE_MS` (150) debounce rides
out a one-frame ray flicker. **Full-body box** (`body_box_for`, 3749, used by the
bodycam full-body outline via `area_box_for`) is the screen-space bounding box of the
projected ragdoll bones (`BODY_BOX_BONES`) — so it tracks the physics ragdoll, unlike
`obj:position()` which stays at the last-alive spot; falls back to a vertical
origin span for non-bip01 rigs. Bodycam outline thickness is `box_thickness` (px,
fixed not distance-scaled), drawn with butted (non-overlapping) corners and
UI_KX-corrected vertical edges (`draw_head_box`).

**Actor-death teardown**: `teardown_ui()` (4273) hides all tag slots, clears
`tracked`, drops cached face ids, and clears the engine redaction. Driven two ways: an
`actor_on_before_death` callback fires it at the **moment of death** (the death
screen can freeze `actor_on_update` with the last frame's tags still drawn, so
the poll alone leaves them on the death screen), plus `actor_on_update` polls
`db.actor:alive()` as a backstop. Idempotent.

**Lua → engine contract** (guarded by `rawget(_G,"bodycam")`, inert on a stock
exe — the box still shows, just no distortion). Multi-rect, SVP-marker style:

```
bodycam.redaction_begin()                 -- start a frame's list
bodycam.redaction_add(x0, y0, x1, y1, …)  -- one face box, NORMALISED [0,1], top-left origin (+ depth, world box)
bodycam.redaction_commit(intensity)       -- publish atomically (intensity 0 / empty list clears)
-- legacy single-rect wrappers kept: set_redaction_rect(...), clear_redaction()
```

`redaction_submit()` (760) converts each box's 1024×768 virtual-space centre/extents
to `[0,1]` (divide by 1024/768, since that virtual space maps across the whole
screen); `intensity` = `redact_strength`.

**Effect variant** (`redact_face_style`, MCM list → engine mode via
`bodycam.redaction_set_mode`, a separate binding so older exes degrade gracefully):
mode = list index − 1, so `0` pixelate (mosaic censor), `1` black box. Passed to the
shader in `redaction_count.y`. (An earlier animated "glitch/redaction" tear mode was
removed; the engine binding names stay `redaction_*` — internal plumbing.)

**Depth mask (never over the viewmodel)**: each box also carries its **view-space
depth** (`view_depth` in Lua = `(headPos − cam_pos)·cam_dir`, matching the engine's
`s_position.z`), threaded through `redaction_add(…,depth)` → `g_bodycam_redaction_depths[]` →
`set_ca("redaction_depths")`. The shader samples the scene depth (`s_position`,
`r2_RT_P`, bound by the blender) and **draws only where the scene surface is within
`band` metres of the box-centre depth, on BOTH sides** — cutting a foreground
occluder (viewmodel, wall) in front AND the background behind, so the effect hugs the
target's depth *slab* instead of a flat rect over everything. For a face box this is
what keeps the distortion off the gun/hands. `band` is **size-adaptive**:
`band = clamp(max(span.x,span.y) × box-depth × REDACTION_BAND_K 0.8,
REDACTION_BAND_MIN 0.45, REDACTION_BAND_MAX 2.5)` — it scales with the box's on-screen
size × depth. A `continue` (not bail) lets an overlapping box still win. depth `0` =
no test (the back-compat wrapper, and the in-scope SVP pass); a **negative** depth is
the FACE flag (front-biased band, § above). The pixelate mode additionally re-checks
each mosaic cell centre against the same slab so it never pulls an off-target colour
into a block.

**Shader** (ships as gamedata, this repo): `gamedata/shaders/r3/bodycam_redaction.ps` —
loaded at runtime by filename, DX11 path (`getShaderPath()` returns `"r3\\"`).
Samples the scene RT via the shared `s_image`/`smp_base`; **loops** the rect array
and, inside the first box a pixel hits (and passing the depth mask), applies the
mode's effect (pixelate = quantise box UV to cells and resample; black = solid —
the exposed modes; an older animated tear/`redaction` effect remains in the shader
but is no longer selectable from MCM), feathered at the edges, scene untouched
elsewhere. Reads `float4 redaction_params (intensity,time,…)`, `float4 redaction_count
(.x = n, .y = mode)`, and `float4 redaction_rects[16]` set from C++ (rect array via
`set_ca`).

**Engine side (custom exe — staged, applied against the fork).** Modeled on the
fork's SVP `draw_scope` region-pass, itself a variant of the stock
`phase_fakescope` (`rendertarget_phase_nightvision.cpp`) + its `CBlender_fakescope`
(`blender_nightvision.cpp`, binds scene RT `r2_RT_generic0` → `s_image`):
1. `CBlender_bodycam_redaction` binding `s_image` + selecting `bodycam_redaction.ps`; `ref_shader
   s_redaction` created in `r4_rendertarget.cpp` (`s_redaction.create(b_redaction,
   "r3\\bodycam_redaction")`).
2. `CRenderTarget::phase_redaction()` — bind `dx10_msaa ? rt_Generic : rt_Color`,
   draw the **fullscreen** `g_combine` quad, `set_c("redaction_rect"/"redaction_params",
   …)`, then `CopyResource` back into `rt_Generic_0`. **No scissor**: the pass is
   fullscreen and the region restriction lives in `bodycam_redaction.ps` (it returns the
   scene untouched outside `redaction_rect`), because `CopyResource` copies the whole
   RT back — a scissored draw would leave the area outside the box stale and
   corrupt the scene on copy-back. Inject in `r4_rendertarget_phase_combine.cpp`
   **after SMAA and TAA** (`phase_ssfx_taa`), immediately before the final
   `combine_2` pass, gated on `g_bodycam_redaction_active && !svp_pass_now`. Placement is
   load-bearing: running it *before* TAA (with the nightvision/fakescope FX) let
   TAA's temporal history rectification clamp the churning redaction out as an
   artifact (a stable overlay like fakescope survives, a per-frame redaction does
   not). After TAA, `rt_Generic_0` holds the finished post-AA scene that
   `combine_2` samples (`s_image = r2_RT_generic0`, `blender_combine.cpp`), so the
   distortion survives straight to screen.
3. Shared state as `ENGINE_API` globals in `xrEngine` (`xr_ioc_cmd.cpp`):
   `g_redaction_rect` (Fvector4, normalised), `g_redaction_intensity`,
   `g_redaction_active`; `bodycam_script.cpp` writes them, the R4 renderer `extern`s
   and reads them (same cross-module channel as `ps_r2_sun_shafts_min`).
4. `bodycam.set_redaction_rect`/`clear_redaction` added to `Bodycam::script_register`'s
   `module(L,"bodycam")[…]`; that `script_register(L)` is called from
   `script_engine_export.cpp`. New `.cpp` files → `xrGame.vcxproj` /
   `xrRender_R4.vcxproj`; game exe target is `AnomalyDX11` (`xrEngine.vcxproj`).
   `set_redaction_rect` stores the rect + sets `g_redaction_active=true`; renderer
   multiplies the `[0,1]` rect by `Device.dwWidth/dwHeight` for the scissor and
   passes the `[0,1]` rect straight to the shader.

Engine changes **applied** to the fork (branch `freeaim-identify-binding`), 7
files + the shader: `xr_ioc_cmd.cpp` (globals), `bodycam_script.cpp` (binding),
`blender_nightvision.{h,cpp}` (`CBlender_bodycam_redaction`), `r4_rendertarget.{h,cpp}`
(member/create/delete), `r4_rendertarget_phase_combine.cpp` (`phase_redaction` +
call). Needs an `AnomalyDX11` rebuild (MSBuild). Step-by-step notes:
`docs/engine-redaction-patch.md`.

## 12. In-scope (SVP/PiP) identification markers (engine)

The mod's `svp_ui_markers_begin/add/commit` + `is_svp_active` calls (gated by
`PIP_AVAILABLE`, a `rawget` existence check) draw identification markers **inside a
PiP scope**. These bindings were written against a PiP engine and **did not exist
in the bodycam fork** — only `is_svp_active` — so `PIP_AVAILABLE` was `false` and
the whole path was inert until Phase 1 built them.

**Phase 1 (engine, validated in-game):** a Lua→shared-buffer→render-pass→shader
pipeline (same shape as the redaction). `svp_ui_markers_*` (registered in
`console_registrator_script.cpp` next to `is_svp_active`) stage a list of
WORLD-space markers into `g_bodycam_svp_markers[16×12]` (12 floats: world xyz, fill
rgba, radius, ring rgb, scanning). `CRenderTarget::phase_svp_markers` projects each
through the **SVP camera** (`Device.matrices[1]`, `mul(mProject,mView)` + clip
divide — the same recipe/source `svp_project_world_point_to_lens` and
`phase_svp_capture` use) and draws a small alpha sprite per marker.

Two placement facts were load-bearing (both cost a bringup cycle): the draw must
go into **`rt_Generic_0`** (the RT `phase_svp_capture` copies into `rt_secondVP`
for the lens to sample — not `rt_Color`/`rt_Generic`), and it must be injected at
the **top of `phase_svp_capture`** (svp_optics.cpp), not the `phase_combine` tail,
because `matrices[1]` is only the live scope camera at capture time. Viewport is
the SVP target's `Width`/`Height`. Shader `gamedata/shaders/r3/bodycam_svp_marker.ps`
(faction disc + relation ring + scanning arc; no in-scope text — infeasible in the
pass). Debug: console `r__bodycam_svp_marker_debug 1`. **No Lua changes** — the mod's
existing code drives it. Phase 2 (richer bracket/sign) not yet built.

**In-scope redaction** (same commit): the face redaction also runs in the scope
(gated by `pip_redact`). `bodycam.redaction_add` gained WORLD box args
(`wcx,wcy,wcz,whw,whh`, stored in `g_bodycam_redaction_world[16×6]`);
`phase_svp_redaction` (called in `phase_svp_capture`, before the markers) reprojects
each world box's 4 camera-facing corners through the SVP camera to a scope-normalised
rect and reuses `bodycam_redaction.ps` **unchanged** (depth `0` = no viewmodel mask
in-scope). Lua-side `head_box_for`/`body_box_for`/`face_box_for` also return the box's
world centre + world half-extents (`body_box_for` accumulates a world AABB of the
bones via the reused `_bbw` accumulator, so the in-scope box tracks the ragdoll too),
and `feed_redaction` no longer bails when scoped — the engine draws the main-camera
rects in the main pass and the world boxes in the SVP pass; the lens only samples the
SVP output, so there's no double-draw. Relies on `SetActive` remapping
`r2_RT_generic0`/`r2_RT_P` to the SVP RTs so the shader samples the scope scene.

## 13. Notes on this document

- This spec was reconciled against the tree at **v2.55.1**. Line-number citations
  point into `ii_identify.script` at that revision — treat them as "near here",
  since the file changes often; the function names are the durable anchors. For a
  release-by-release view of behaviour changes, see **`CHANGELOG.md`**.
- **`README.md`** — verify its optional-component list matches the three components in
  `ModuleConfig.xml` (FactionID Neutralized, Perception Skill Integration,
  st-wearable-devices Compatibility).
