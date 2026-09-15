# Changelog

## 3.1.0 — everything since 2.53.0

Summarizes changes from **v2.53.0** to **v3.1.0**, grouped by area (final behaviour, not
per-edit). Features marked **(custom exe)** need the companion `xray-monolith-bodycam` engine
build; everything else works on stock Anomaly / GAMMA and stays inert when a binding is absent.
The big-ticket items are two new UI styles, free-aim identification for *every* held item, a
restructured MCM, and a full **Wearable Devices** compatibility add-on (its own section below).

### New UI styles
- **Crooks** — instead of world-anchored tags, a single **static on-screen readout** of the
  **last identified** stalker: faction **logo** + name, with the **rank** optionally below it.
  Anchors to a screen corner (bottom-left / middle / right) with X/Y offset sliders. It follows
  your gaze (re-aiming a known target re-points to it) and respects the identification linger.
- **Simple** — a compact horizontal strip above the head: relation-coloured dot + glow, then
  the faction logo, then the name.

### Free-aim identification (now works for every held item)
- Aiming with a **firearm** uses the standard engine weapon trace (`ETraceTarget.Weapon`),
  which is barrel-accurate and now works on **any** exe — including stock xray-monolith. (This
  had been silently dead: `ETraceTarget` is a global enum we were reading under `level`.)
- **Knife / raised binoculars** have no real weapon barrel, so they fall back to the actor's
  first-eye aim camera via `bodycam.get_fire_ray()`. **(custom exe** for knife/binoc only;
  firearms work everywhere.)

### Target assist
- **Reverted to a straight screen-radius assist** (the 2.53 angular cone is gone): a target is
  acquired when its nearest body point projects within `fov_radius` px of the aim point.
- **Aiming directly at a stalker always identifies them now** — a direct **model raycast**
  ("what the crosshair is on") takes priority over a merely-nearby target, fixing the case
  where a tight radius or aiming between bones let another target steal the pick.
- New **"Only show overlay while aimed"** toggle (default off): overlays show only while you're
  aiming at/near the target and reappear when you aim back; identification still completes.

### New identify modes & timing
- **Hipfire dwell mode** (its own MCM page): auto-identify a target held under your hip-fire
  aim for a configurable hold time — no keypress.
- **Per-mode "exclude from instant identify"** toggles (Hipfire / ADS / Binoculars): with
  Instant identify on, keep the normal scan wait for a chosen mode (e.g. instant hip-fire but a
  delay through binoculars).
- **Hold times and fade duration can now be 0** — ADS / hipfire / binocular dwell can identify
  the instant you aim; fade duration 0 gives an instant reveal.
- Re-aiming a **faded-out** tag now restarts its **fade-in** (respecting fade duration) instead
  of popping in at full alpha.

### Binoculars
- Fixed the identify-range boost blowing far past the intended distance. With **scale by
  magnification** on, the range now tracks the binocular's **real current magnification**
  (~1.7–4.4×, from the SVP/PiP engine value, read directly so it isn't dropped by a flickering
  scope gate); **off**, it uses the flat max-distance multiplier as before.

### MCM
- **UI Style is now an expandable section** with **General / Bodycam / Crooks** sub-pages.
- New **Crooks** preset (instant identify in all modes + the Crooks UI); presets are now
  Card / Minimal / Bodycam / Immersive / Crooks.
- **Show rank** toggle (gates the rank line on Card / Bodycam / Crooks).
- **Max distance** slider steps in 5s.
- The **Wearable Devices** page is hidden unless the WD compat component is installed.
- Debug: **"Simulate stock engine"** toggle — run the stock-engine fallbacks without the custom
  exe, for testing.

### Fixes & housekeeping
- **Removed the depth-aware Bodycam box** rendering — the outline box now always draws as flat
  edges (always on top), dropping the custom-exe dependency for the box itself.
- Fixed the **haru Skill System crash on level-up** when the Perception integration was
  uninstalled from a save that had used it (an orphaned skill): the mod no longer feeds XP to a
  perception skill that isn't currently configured.
- Fixed the **"Require Scanner kit to identify"** toggle reading a disabled checkbox as enabled
  (MCM marshals `0`, which is truthy in Lua) — all boolean options are now coerced safely.
- Removed the custom bodycam free-aim binding, then restored it as the knife/binocular fallback
  once the standard weapon trace was found to cover firearms.

### st-wearable-devices compatibility (new optional FOMOD component)
Gates identification behind wearable scanner gear from the **st-wearable-devices** mod via a
module/scanner **tier system**. Entirely optional and self-contained — the base mod is inert
without it (an `ii_identify.tier_provider` seam, snapshotted per frame). See
`WD Compatibility/README.md`.

- **Two identification channels, independently installable:**
  - **AR Scanner** — a worn bracer device (3 tiers, range 10/20/30 m; scope-ADS + magnification
    boost at T2, no night penalty at T3). Shows identification **on entities** as usual. Needs
    the antenna + a process module in the Promin.
  - **OSD Scanner Module** — a Promin module (3 tiers). Shows identification **only on the
    Promin IDENTIFICATION page**, no on-entity UI. Needs only the OSD module + a process module.
  - With both installed you get entity overlays **and** the Promin readout at once.
- **Promin modules** — antenna, process (T1–3), OSD scanner (T1–3) — install through WD's own
  system and show in the bracer customize screen with their icons. The mod adds a **4th Promin
  bay** so antenna + process + OSD scanner + WD's map can all be installed together (ships an
  override of WD's customize screen for the 4th cell). One module per bay (installing a new tier
  swaps the old). The AR scanner is a worn bracer device but invisible (no model).
- **Process tier** sets scan speed + progressively unlocks the data shown (faction/distance →
  relationship/rank → weapon). **Binoculars** work under the tiers (unlock at T1 by default).
- **Promin IDENTIFICATION page** (added by an OSD scanner): the last-identified target with a
  **portrait**, name, faction, rank, position, distance, weapon+caliber (locked fields show
  `---`), an animated **scanning spinner** while scanning, and a **baked 3-tab strip**
  (IDENTIFICATION / BIOMONITOR / NAVIGATION) shown on every page. Since the Promin CRT has no
  font, this ships a monospace glyph-texture atlas + text compositor and overrides WD's
  `d_promin_ui.script` to register the page. Readout respects scan time (appears on completion).
- **Identification notification pop-ups** on the BIOMONITOR / NAVIGATION pages: a card
  (faction emblem, name + distance, rank as a level) pops up bottom-right and stacks up.
- **Wearable Devices MCM page** to tune every tier value, plus a master **ignore Wearable
  Devices** toggle and **require-kit** toggle. The page is hidden unless the component is
  installed.
- Crafting recipes for every item (tool-tier gated; higher tiers consume the previous tier +
  Promin tech) and generated inventory icons.

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
