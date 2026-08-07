# Immersive Identification

A S.T.A.L.K.E.R. Anomaly / GAMMA mod: aim at an NPC or creature and press a
bindable key to identify them. Instead of a HUD element, the result is a
floating tag anchored to the target's own body in 3D world space — a small
rotating spinner on their body while it "scans", then a compact row that
fades in above them: a relation-coloured dot (red = enemy, green = friend,
tan = neutral), their faction patch, and their name. No background plate, no
box, no persistent screen-space UI — just those elements anchored to the
target while active.

Built for the engine exposed by this repo (`xray-monolith`) and modelled on
the projection/render technique used by
[Immersive Quest Markers](https://github.com/themrdemonized) — see
"Implementation notes" below for exactly which engine APIs this relies on.

## Install

### Mod Organizer 2 (FOMOD)

`immersive-identification-fomod.zip` (built from `fomod/` + `gamedata/` in
this repo) is a ready-to-install FOMOD archive:

1. In MO2: **Install Mod...** and point it at `immersive-identification-fomod.zip`
   (or drag the zip into the MO2 window).
2. The mod has no install-time options, so it installs directly — no wizard
   steps to click through.
3. Enable it in your mod list like any other mod.

To rebuild the zip after editing the mod (from this directory):

```
zip -r -X ../immersive-identification-fomod.zip fomod gamedata README.md
```

### Manual

Copy the `gamedata` folder into your Anomaly/GAMMA install (or add it as a
MO2 mod pointing at this folder). No other mod is required; MCM (Mod
Configuration Menu) is optional but recommended for configuring the key/timing.

```
<repo>/gamedata  ->  <anomaly install>/gamedata
```

## Use

1. Aim near an NPC or creature — you don't need a pixel-perfect hit. If you
   have a weapon out, a direct hit traces from the weapon's own barrel
   alignment (the same trace the engine uses for firing), not the camera
   centre. Unarmed, a direct hit falls back to the camera trace. Either way,
   if you don't land directly on someone, the nearest identifiable,
   *visible* target within an invisible on-screen radius around the
   crosshair is picked instead — targets behind walls or buildings are
   skipped even if they'd otherwise be the closest match on screen.
2. Press the identify key (default **X**; click into the key box in MCM
   under "Immersive Identification" and press any keyboard or mouse button
   to rebind it). Optionally require Ctrl, Shift, or Alt held too, via the
   modifier dropdown next to it — pick one, or "None".
3. A small spinner rotates on their body for a moment, then a row fades in
   above them — relation dot, faction patch, name — holds for a few seconds,
   and fades out.
4. Re-pressing the key on an already-identified target restarts the reveal.
   Up to 5 identifications can be active at once (oldest is dropped first).

Everything is configurable in MCM: enable/disable, the key + modifier,
relation colouring, scan/fade/hold durations, max/fade-out range, and the
target-assist radius (pixels, plus a line-of-sight toggle).

## Files

```
fomod/
  info.xml            -- FOMOD metadata (name/author/version/description)
  ModuleConfig.xml     -- FOMOD install script (no options: installs gamedata/ as-is)
gamedata/
  scripts/
    ii_identify.script   -- core logic: input hook, identify state machine, CUI render
    ii_mcm.script         -- MCM options page (reads defaults from ii_identify.script)
  configs/
    ui/
      ii_tags.xml                       -- CUI element templates for the tag
      textures_descr/ii_textures.xml    -- texture atlas -> file mapping
    text/eng/st_ii_texts.xml            -- MCM strings + faction display names
  textures/ui/
    ii_white.dds     -- solid tintable square (plate / accent bar)
    ii_dot.dds       -- soft tintable circle (relation dot / glow)
    ii_spinner.dds   -- comet-tail ring (rotated at runtime: the scan spinner)
```

The three textures are generated flat/procedural placeholders so the mod has
zero dependency on any other mod's art. Swap them for hand-made art any
time — every element is tinted at runtime via `SetTextureColor`, so
replacements just need to keep white RGB with the shape carried in alpha.

## Implementation notes

Ground-truthed against this repo's C++ (`src/xrGame/level_script.cpp`,
`src/xrGame/script_game_object_script*.cpp`, `src/xrGame/Level_input.cpp`)
and against the working `iqm_markers.script` in
`gamma-immersive-quest-markers` for exact Lua-side call syntax:

- **Target**: `level.get_target_obj(level.ETraceTarget.Weapon)` first — this
  reads the equipped weapon's own hit-test (`src/xrGame/level_script.cpp`,
  `get_pick(TT_WEAPON)` → the attached hud item's `GetPick()`), the same
  barrel-aligned trace the engine uses for firing, not the camera centre.
  Falls back to `level.get_target_obj()` (camera trace) when unarmed or the
  weapon trace hit nothing. If neither raycast hits anything, falls back
  further to a target-assist search (no on-screen indicator; purely a
  selection radius): `level.iterate_nearest(actor_pos, max_dist, functor)`
  (confirmed at `src/xrGame/level_script.cpp:2117-2137` — objects pre-sorted
  by *world* distance to `actor_pos`, functor return `true` stops early)
  walks every candidate within range, each one projected to screen space
  with the same `world2ui` used for rendering, and the functor keeps the one
  closest to screen centre (512,384) within `fov_radius` px instead of
  stopping at the first/nearest-in-world hit — since the ranking needed is
  screen distance to the crosshair, not world distance to the actor, the
  full candidate set has to be walked rather than relying on the pre-sort.
- **Line of sight**: each target-assist candidate is additionally checked
  with `level.ray_pick(eye_pos, dir, dist, level.rq_target.rqtStatic,
  level.rq_result(), nil)` (signature and the `level.rq_result()`
  constructor confirmed at `src/xrGame/level_script.cpp:2080-2094,2654-2673`)
  from the camera eye (`device().cam_pos`) toward roughly chest height on the
  candidate; if a static hit lands closer than the candidate itself, they're
  behind something and get skipped even if they're the closest screen-space
  match. Toggleable (`require_los`); the raw raycast hits (weapon/camera
  trace) don't need this check since a ray physically can't pass through
  static geometry to begin with.
- **Faction**: `obj:character_community()` — a string id ("stalker",
  "bandit", "dolg", ...).
- **Name**: `obj:character_name()`, falling back to a faction display name
  (from the mod's own string table, prettified-id fallback for anything
  unlisted) for mobs/monsters with no personal name.
- **Faction patch**: `CUIStatic:InitTexture("<community_id>_icon")`, reusing
  the exact texture-id convention the game's own character/relations UI uses
  for faction emblems (`src/xrGame/ui/UICharacterInfo.cpp:186-208`) — no
  bundled icon art needed, but see Caveats below.
- **Relation colour**: `obj:relation(db.actor)` compared against the
  `game_object.enemy` / `.friend` / `.neutral` enum (confirmed at
  `src/xrGame/script_game_object_script2.cpp:38-45`).
- **Key bind**: hooks `level_input.on_key_press(key, action, disabled)`
  directly (the exact function the engine calls from
  `CLevel::IR_OnKeyboardPress`), chaining any pre-existing definition so it
  composes with other mods instead of clobbering them. The captured key
  comes from an MCM `type = "key_bind", val = 2` widget (`ii_mcm.script`'s
  `key_dik` option; `def` is the raw `DIK_keys.DIK_X` value directly, same
  as any other captured DIK), which `ui_mcm.get("ii/main/key_dik")` then
  returns as a plain DIK integer read straight into `C.key_dik`. The
  optional Ctrl/Shift/Alt modifier is a single `type = "list"` dropdown
  rather than three checkboxes, checked via `key_state()` (polled at press
  time, not part of the captured bind) against both the left and right DIK
  variant of whichever one is selected.
- **World anchor**: walks a short list of humanoid bones
  (`bip01_head` → spine chain) via `obj:bone_position(name)`, sanity-checked
  against `obj:position()` (bone lookups are exception-safe in this engine
  and silently return a zero vector on a missing bone, so a distance check
  is required rather than trusting a non-nil result), falling back to
  `position() + vertical offset` for skeletons without those bones.
- **World-to-screen**: `game.world2ui(pos, false, false)` (confirmed as a
  stock global alongside `level.world2ui`; the mod tries `game` first and
  falls back to `level` defensively), returning 1024x768-space coordinates
  with `x < -9000` signalling off-screen/behind-camera.
- **Rendering**: a pool of `CUIScriptWnd`-hosted `CUIStatic`/text elements
  built once from `ii_tags.xml` and repositioned every `actor_on_update`
  frame (no per-frame allocation of UI objects), attached once via
  `get_hud():AddDialogToRender(...)`.
- **Scan spinner**: a comet-tail ring texture (`ii_spinner.dds` — alpha fades
  around ~80% of the circumference so it reads as a rotating arc, not a
  static ring) rotated continuously via `CUIStatic:EnableHeading(true)` +
  `:SetHeading(radians)` (the same rotation mechanism proven by the
  reference mod's leader-line rotation), angle driven by `time_global() %
  900ms` for a steady ~0.9s spin.

## Caveats / things to verify in-game

This was written against engine source and a working reference mod without
a live Anomaly/GAMMA install to test against, so a few things are worth a
sanity check on first run:

- The `<w>`/`<texture>`/`<text>` XML attribute set in `ii_tags.xml` mirrors
  `iqm_cards.xml` exactly; if a font or alignment value renders oddly, check
  those two files side by side.
- Only English strings are shipped (`configs/text/eng`). Add
  `configs/text/rus/st_ii_texts.xml` with the same string ids for Russian.
- `FACTION_NAMES` in `ii_identify.script` covers the common vanilla/GAMMA
  community ids; anything else still displays (via the prettified-id
  fallback) but won't have a curated display name until added there.
- The target-assist scan (`find_nearest_in_fov`) only runs on a key press,
  not per-frame, but it does call `world2ui` (and, for the closest-so-far
  candidate at each step, `ray_pick` for the line-of-sight check) once per
  nearby candidate. At the default 60m `max_dist` that's negligible; if you
  push `max_dist` up toward its 500m ceiling in a busy area, expect the odd
  frame hitch on the identify keypress itself (not sustained, since it's not
  a per-frame cost).
- **The line-of-sight ray_pick out-parameter pattern is the one piece of API
  usage here I'm least certain of.** `level.ray_pick(start, dir, range, tgt,
  result, ignore)` takes `result` as a non-const C++ reference the function
  writes into; I construct it once via the confirmed `level.rq_result()`
  constructor and reuse it, which is the standard luabind calling
  convention for a plain reference parameter with no default constructor
  hidden behind it. It's `pcall`-wrapped and fails open (treats an error as
  "visible") specifically because I couldn't test this against a live
  engine — if targets past walls are still getting picked, or valid targets
  in the open are getting skipped, this is the first place to check; toggle
  `require_los` off in MCM as an immediate workaround either way.
- **Faction patch textures are not bundled.** They're loaded by id
  (`"<community_id>_icon"`, e.g. `"stalker_icon"`, `"dolg_icon"`) from
  whatever's already registered in your Anomaly/GAMMA install's own texture
  descriptors, since that's the exact id the game's own relations UI uses
  internally. This is very likely present for the standard factions, but
  isn't verified against a live install — if a patch doesn't show for some
  community, the `InitTexture` call is pcall-guarded so it just leaves the
  patch blank/placeholder rather than erroring, and the dot + name still
  work fine. If patches are missing in practice, bundling dedicated icon
  textures under `gamedata/textures/ui/` and mapping them in
  `ii_textures.xml` (same pattern as `ii_white`/`ii_dot`) is the fix.
