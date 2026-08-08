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
Immersive Quest Markers

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

The dot, faction patch, and spinner scale with distance — bigger up close,
smaller far away (name text stays a fixed size); toggle this and its min/max
scale in MCM.

Everything is configurable in MCM: enable/disable, the key + modifier,
relation colouring, scan/fade/hold durations, max/fade-out range, the
target-assist radius (pixels, plus a line-of-sight toggle), distance
scaling, and binocular mode.

Raising binoculars always makes identification faster and extends its range
(default: ~2.5x range, reveals in ~40% of the normal time) — this applies
with the regular key too, independent of Binocular mode below. Toggle it and
tune both multipliers in MCM.

Farther targets also take longer to scan by default (up to 3x right at your
max range), scaling smoothly from instant up close — and since binoculars
extend that max range, the same physical distance reads as proportionally
closer through them, on top of their own flat speed bonus above. Toggle and
tune in MCM.

### Binocular mode

Turn this on in MCM and identification changes from "press a key" to "raise
the binoculars and hold still": the key stops working unless you're actively
looking through the binoculars (not just holding them — has to be zoomed
in), and while you are, aiming near a target and holding the aim steady for
a moment (configurable, default 0.6s) identifies them automatically — no key
press needed. Move the aim off them (or past the steady tolerance) to reset;
holding steady on them again re-triggers it.
