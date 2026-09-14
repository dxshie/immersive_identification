# Changelog

## Unreleased

- **Fixed: the Crooks readout wouldn't re-show the first target when looking back and forth.**
  The last-identified snapshot was captured once per target (on scan completion), so re-aiming
  an already-identified stalker never re-pointed it — and Crooks (which draws only that
  snapshot, no per-entity tag) stayed stuck on the last *new* scan. The Crooks readout now
  follows your gaze: re-aiming an identified target re-points to it. (Other styles were fine —
  they redraw each target's own tag.)
- **Crooks** can now show the stalker **rank** below the name (gated by the new **Show rank**
  toggle).
- New **Show rank** toggle (UI Style page, default on) — gates the rank line on Card / Bodycam
  and the Crooks readout, matching Show name / faction / weapon.
- **Fade duration can now be set to 0** (instant reveal + instant fade-out; the fade math is
  divide-by-zero-safe at 0).
- **Fixed: re-aiming a faded-out tag popped in instantly instead of fading.** Going back and
  forth between targets, a tag still lingering in its fade-out now restarts its fade-*in*
  (respecting fade duration) rather than snapping to full; a tag still in hold just refreshes
  (no flicker while continuously viewed).

- **Fixed: aiming directly at a stalker sometimes wouldn't identify** (and would only work
  after looking at others and back). The FOV assist selects the target whose nearest *bone*
  falls within `fov_radius`, so with a tight radius — or aiming at the model *between* the
  sampled bones — a merely-nearby other target could win selection instead of the one you're
  pointed at. Target selection now prioritises a **direct model raycast** ("what the crosshair
  is actually on") above the nearby-in-cone pick, so aiming straight at someone always
  identifies them. The **"Only show overlay while aimed"** gate honours the same direct-model
  hit, and the **Crooks** readout with it.

- New **"Crooks" MCM preset**: instant identify in **all** modes (hipfire / ADS / binoculars,
  hold times = 0) with the **Crooks** UI, FOV assist + free aim on, and a ~25% FOV radius.
  (`steady_time` can now reach 0 for instant binocular identify.)
- New **"Only show overlay while aimed"** toggle (Targeting page, default off): a target's
  identification overlay shows only while you're aiming at/near it (within the FOV radius),
  and reappears when you aim back. Identification itself still completes.
- The **Crooks** readout now shows the **faction logo** (not the faction name) and drops the
  `|` separator, and **respects the identification linger** — it stays only while the target's
  reveal window is active, then hides (rather than lingering forever).
- New **Crooks** UI style: instead of world-anchored tags, a single **static on-screen
  readout** of the **last identified** stalker — `FACTION | NAME`, faction-coloured. Anchors
  to a screen corner (**bottom-left / middle / right**, MCM "Crooks: screen position") with
  **X/Y offset** sliders to nudge it anywhere. No on-entity UI in this mode.

- **Free-aim identification now works for every held item** (firearm, knife, binoculars).
  Firearms use the standard engine weapon trace (`get_target_obj/pos(ETraceTarget.Weapon)`),
  which is barrel-accurate and works on any exe — including plain xray-monolith (the enum is a
  global `ETraceTarget`, a namespace trap we'd been reading wrong). Knife / raised binoculars
  have no meaningful weapon barrel (their weapon trace is the cosmetic HUD model), so those
  fall back to the actor's first-eye aim camera via the custom `bodycam.get_fire_ray()` binding
  — the only source that reflects free aim for non-firearms. The binding is guarded, so
  firearms still work without the custom exe; only knife/binoc free-aim needs it.

- **Fixed the `ETraceTarget` weapon-trace lookup.** It's a *global* enum (the engine
  registers it in `module(L)`, not under `level`), so our `level.ETraceTarget` guard was
  always nil and the whole `get_target_obj/pos(Weapon)` path was dead. Now read from the
  global — the standard engine weapon trace (which builds off the barrel matrix, so it should
  reflect free-aim) is live again.
- **New "Use bodycam fire-ray binding" toggle** (Targeting MCM page, default on): turn off to
  disable our custom `bodycam.get_fire_ray()` engine binding entirely and rely only on the
  standard `ETraceTarget.Weapon` trace — for A/B testing the two free-aim sources, or running
  without the custom exe.

- **FOV target-assist reverted to a straight screen radius.** The angular-cone logic (which
  reinterpreted `fov_radius` as an angle measured from the aim ray) has been removed — the
  assist once again acquires the target whose nearest body point projects within `fov_radius`
  screen pixels of your aim point, which fits this mod's use better. When nothing falls inside
  the radius it still falls back to a **model raycast** along the true aim ray (identify what
  you're directly pointing at — too close, or aiming just off the silhouette). LOS respected.
- **ADS and hipfire hold time can now be set to 0** (sliders reach 0) for instant
  identification the moment you aim at a target — no dwell wait. At 0, the dwell fires on the
  same frame the target is acquired.
- **New "Ignore Wearable Devices entirely" master toggle** (Wearable Devices MCM page): when
  on, the whole WD compat integration is bypassed and identification works exactly as if the
  compatibility component were never installed (no kit, no tiers). Overrides the rest of that
  page.
- Removed the **depth-aware Bodycam box** rendering: the outline box no longer submits
  world-anchored rects to the engine's depth overlay (occluded per-pixel by walls/viewmodel)
  — it now always draws as flat CUIStatic edges (always on top). Removes the custom-exe
  dependency for the box. (The depth-aware *text* name-lines are a separate path, unchanged.)
- New **Simple** UI style: a compact horizontal strip above the head — the Card style's
  relation-coloured dot + glow, then the faction logo, then the name.
- New **Hipfire dwell mode** (Targeting MCM page): auto-identify a target held under your
  hip-fire aim (not ADS, not binoculars) for a configurable hold time — for players who'd
  rather not press the identify key and still identify from the hip.

### st-wearable-devices compatibility (new optional FOMOD component)
- Gates identification behind wearable scanner gear from the **st-wearable-devices** mod
  via a module/scanner **tier system**. New items (placeholder art): a Promin **Antenna**
  module, a 3-tier Promin **Process** module (scan speed + progressive data unlocks:
  faction/distance → relationship/rank → weapon), and a 3-tier worn **Identification
  Scanner** (range 10/20/30 m; scope-ADS + magnification boost at T2; no night penalty
  at T3). With the full kit assembled, the tiers drive identification and override the
  matching MCM settings; `wd_require_kit` (default on) blocks identification without it.
- New **Wearable Devices** MCM page overrides every default tier value (process scan
  times, scanner ranges, and which tier unlocks each feature).
- Core: an optional `ii_identify.tier_provider` seam (snapshotted per frame) + a new
  **distance-to-target** readout on the name line; both fully inert without the add-on.
- Modules install into the Promin through WD's own system and **show in the bracer
  customize screen** (with their icons) — done by repurposing WD's two functionally-empty
  Promin bays (`conn`→antenna, `side`→process), so no new bays and no customize-UI crash.
  Process tiers are mutually exclusive (installing one swaps out the other). The scanner is
  a worn bracer device but **invisible** (no worn model).
- Custom generated inventory icons for the antenna (broadcast antenna), process module
  (IC chip), and scanner (radar display).
- **Promin IDENTIFICATION tab**: installing the antenna adds a third Promin screen page
  (cycled with the others) showing the last-identified target — name, faction, rank,
  position, distance, weapon+caliber (locked fields show `---`). Since the Promin CRT
  screen has no font, this ships a monospace glyph-texture atlas + a text compositor (the
  same per-character-texture technique WD uses for its clock) and a VFS override of WD's
  `d_promin_ui.script` to register the page.
- `ii_identify.get_last_identified()` exposes the last-identified target for external
  readouts (main mod; inert without a reader).
- Crafting recipes for every item (antenna, process T1-3, AR + OSD scanner T1-3), mirroring
  WD's own recipe format; higher tiers consume the previous tier + Promin tech.
- **Identification notification pop-ups on the Promin.** When a target is identified while
  you're on the **BIOMONITOR** or **NAVIGATION** page (not the IDENTIFICATION page, where it's
  already shown), a card pops up bottom-right and stacks upward as more come in: faction
  emblem (left), name + distance (middle), and rank shown as a level ("Rank 1"…"Rank 8",
  mapped from the rank name) on the right. Cards expire after a few seconds. Author-provided
  card art (`ii_wd_notif_card.dds`).
- Added a **4th Promin module bay** so the antenna, OSD scanner, process module, and WD's
  map module can all be installed at once (previously the antenna and OSD scanner shared one
  bay). The OSD scanner now lives in its own bay, so the **AR and OSD channels are
  independent** — run entity overlays and the Promin readout simultaneously if you have both.
  Requires a shipped override of WD's `ui_wd_customize.xml` (adds a 4th module cell — WD's
  screen only ships three and a 4th bay otherwise crashes it).
- **Binocular support under the tier system** (both AR and OSD): a scanner tier now unlocks
  identifying through raised binoculars, extending the identify range by the binocular range
  multiplier. Unlocked at Tier 1 by default; configurable on the Wearable Devices MCM page.
- Two scanner channels: **AR Scanner** (a worn bracer device, the old scanner renamed) —
  identification shown ON entities as usual, needs the antenna; and **OSD Scanner Module**
  (a Promin module) — identification shown only on the Promin IDENTIFICATION page, no
  on-entity UI, and needs **only the OSD module + a process module** (no antenna). The OSD
  module shares the Promin `conn` bay with the antenna (mutually exclusive = the AR/OSD
  switch). Both come in the same 3 tiers. Face redaction is unaffected. New AR Scanner icon
  (viewfinder brackets over a target); the OSD module reuses the radar icon.
- Fixed the missing line break after "FEATURES:" in item descriptions (a `\n` right after a
  `%c` colour tag was dropped by the engine's text parser; moved it inside the coloured run).
- The IDENTIFICATION tab is now a **real baked tab** in the Promin's top strip, shown on
  **every** page (IDENTIFICATION / BIOMONITOR / NAVIGATION), with the active one highlighted
  and the font matching WD's. Uses author-provided background art (DXT5, matching WD's
  format): the identification page has its own `tablet_ui_main_ident.dds`, and the biomonitor
  and navigation page backgrounds (`tablet_ui_main.dds`, `tablet_ui_main_map.dds`) are
  overridden so the three-tab strip appears consistently across all pages.
- The Promin IDENTIFICATION page now shows an animated **scanning spinner** (over the
  portrait area) while a scan is in progress; the text fields keep the last result until the
  new scan completes. Driven by a new `ii_identify.get_scan_progress()`.
- Fixed the **OSD scanner's Promin readout ignoring scan time**: the target now appears on
  the Promin IDENTIFICATION page only when the scan actually **completes** (a slower process
  module = a longer wait), and the previously-identified target stays shown until the new
  scan finishes — mirroring when an on-entity tag reveals. It previously populated instantly
  at scan start.
- Fixed the **binocular identify-range boost** blowing far past the intended distance. With
  `binoc_zoom_scaling` on it multiplied the range by the camera-FOV ratio (the raw angular
  zoom, e.g. ~19.6x) instead of the configured magnification, e.g. a 50 m base became ~977 m
  instead of `50 × 4.4 = 220 m`. Binoculars now use `binoc_range_mult` directly as the
  magnification; `binoc_zoom_scaling` reserves a seam for a real engine-reported magnification
  (custom exe) and is inert (flat multiplier) without it — never FOV-derived.
- Fixed the **Wearable Devices → "Require Scanner kit to identify"** toggle: disabling it
  still blocked identification. MCM marshalled the checkbox as the number `0`, which is
  truthy under Lua `if`, so a disabled box read as enabled. `read_config` now coerces every
  boolean-default option to a real boolean, hardening all checkboxes against the same trap.
- The Promin IDENTIFICATION page now shows the target's **portrait** (its character_icon)
  alongside the text fields, and lays out like the NAVIGATION page — biomonitor kept on
  the left, identification info in the right panel where the map is, with an
  "IDENTIFICATION" tab label in the empty tab slot next to BIOMONITOR / NAVIGATION.
- **Not verified in-game** — the WD device/slot integration follows WD's patterns but
  needs in-game iteration. See `WD Compatibility/README.md`.

## 2.53.0 — everything since 2.0.1

This summarizes the changes from **v2.0.1** (first bodycam aim-logic build) up to
**v2.53.0**, grouped by area rather than by point release. Features marked
**(custom exe)** need the companion `xray-monolith-bodycam` engine build; everything
else works on stock Anomaly / GAMMA and stays inert when a binding is absent.

### Bodycam UI style (new)
- New **Bodycam** UI style: an unfilled, faction-coloured outline box locked to the
  target's head bone, auto-scaled with distance so it stays a constant real-world size.
- Box options: **area** (head/face vs full body — full-body tracks the ragdoll),
  **colour source** (faction colour vs relation red/green/grey), **thickness**,
  **padding**, and **opacity**.
- Target **name** and **weapon + caliber** shown beside the box.
- Depth-aware box overlay that draws over the world but is masked off the viewmodel
  (never paints over the gun/hands) and sits under the HUD. **(custom exe)**

### Identification
- **Instant identify** option — skip the scan/spinner and reveal immediately.
- **Hide when unseen** — drop an active tag the moment the target ducks behind cover.
- **Weapon + caliber** display option.
- Don't restart an identification already in progress: re-triggering a target that's
  mid-scan (or already revealed) no longer restarts it — scans finish, revealed tags
  just refresh their hold window.
- Identification no longer sees through walls (line-of-sight gating), with
  **multi-point LOS**: a target counts as visible if its head *or any* body part has a
  clear line, so a covered head with an exposed body still identifies.

### Target assist
- **FOV target-assist**: identify a target you're aiming *near* without a pixel-perfect
  hit — with an assist radius and a master toggle.
- **Free-aim assist**: centres the assist on where the weapon actually points under
  bodycam free-aim (barrel ray while ADS, eye ray at the hip). **(custom exe)**
- Rebuilt the assist as an **angular cone** measured from the true aim ray:
  magnification-invariant and immune to bodycam sway, so it behaves the same hip-firing
  or scoped at high zoom (replaces the earlier screen-space ring / adaptive radius).
- Assist radius slider range widened to 0–180.

### Aim-down-sight (ADS) mode (new)
- **ADS mode**: auto-identify on a steady aim-down-sight, like binocular mode.
- ADS **range/scan boost** with optional **magnification scaling** (higher-power optics
  reach further), and an option to **hide the main HUD** while aiming.
- ADS detection via the stock weapon-zoom callbacks, so it works on any exe and for 1×
  optics that don't change the FOV.
- Steady-aim now sweeps and identifies **every** target inside the assist zone (not just
  one) and keeps catching new ones while held steady.

### Binoculars
- Binocular **range/scan boost** (independent of binocular mode), a dedicated
  **binocular FOV-assist** toggle, and optional **magnification scaling**.
- Default binocular range multiplier raised to 4.4×.

### PiP / in-scope UI (new, custom exe)
- Identification UI rendered **inside** a PiP scope: a faction dot, relation ring, and
  scanning spinner drawn in the scope's own view.
- Options to toggle in-scope markers, in-scope redaction, and hiding the main HUD while
  scoped.
- Hybrid **scope-magnification** detection (PiP engine value, or recovered from the FOV),
  used to extend ADS range.
- In-scope markers scale with distance so a far target's dot no longer overlaps its head.

### Redaction (new, custom exe)
- **Face redaction**: a pixelate or black-box censor over the faces of humanoids in
  range (alive or dead), with its own range, strength, style, and padding, plus a
  separate reach from the identify range.
- Runs both on the main view and inside a PiP scope.
- (An earlier corpse-redaction feature was added and later removed as unreliable.)

### Debug tools (new)
- **Debug draw**: on-screen visualiser of the target assist — aim dot, assist ring,
  per-entity bone dots coloured by range with distance labels, and a status line showing
  mode, applied range multiplier, scope magnification, and the assist cone angle.
- Mod logging writes to its **own file** (`appdata/logs/immersive_identification.log`),
  separate from the shared game log.

### MCM
- **Presets** (Card / Minimal / Bodycam / Immersive) selectable from the menu.
- Reorganised menu with proper section titles, captions, and hover tooltips.

### Fixes & housekeeping
- Fixed the scope magnification "sticking" at the last scope's zoom after unscoping.
- Fixed ADS reading as "hip" when bodycam camera logic is disabled.
- Fixed the loading spinner and several targeting edge cases.
- Renamed the redaction shader/effect from "glitch" to "redaction" throughout.
- StyLua formatting, XML linting, and packaging tooling; internal refactors and staying
  within Lua 5.1's per-chunk local limit.

### Requires the custom engine
The bodycam UI overlay, free-aim assist, PiP in-scope UI, and redaction depend on the
`xray-monolith-bodycam` engine build. On stock Anomaly these paths stay inert and the
Card/Minimal styles and standard identification work normally.
