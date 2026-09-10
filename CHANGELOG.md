# Changelog

## Unreleased

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
- Custom generated inventory icons for the antenna (broadcast antenna) and process module
  (IC chip); the scanner keeps a placeholder icon.
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
