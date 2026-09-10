# Immersive Identification — st-wearable-devices Compatibility

Optional FOMOD component. Install **only** alongside both **Immersive Identification**
and **st-wearable-devices** (WD). It gates identification behind wearable scanner gear
and a module tier system. See `SPEC.md` §7.3 for the full design.

## What it adds

- **Promin Antenna Module** — establishes the scanner↔Promin link (required).
- **Promin Process Module (Tier 1/2/3)** — sets scan speed and gradually unlocks the
  data shown: faction + distance (T1), + relationship + rank (T2), + weapon (T3).
- **Identification Scanner (Tier 1/2/3)** — worn on the bracer; sets range
  (10/20/30 m) and unlocks scope/ADS support + a magnification range boost (T2) and
  no-night-penalty (T3).

With the full kit assembled (bracer worn + Promin worn & powered + an antenna and a
process module **installed** + a worn scanner), identification runs on the tiers. Tune
every default on the **Wearable Devices** page of the Immersive Identification MCM.
`wd_require_kit` (default on) blocks identification entirely without the kit; turn it off
to keep normal identification when the kit isn't complete and let the tiers only enhance
it.

## How the modules install

Wear the Promin, then install the antenna and a process module through **WD's own system**
— the item's use menu (**"Install module"**) or the **bracer customize screen**, where
they show in the module cells with their icons. Remove them via the Promin's own remove
option (WD's use3). The antenna occupies one module cell, the process module another; only
one process tier fits at a time (installing a different tier **swaps it out**, returning
the old one to your pack).

This works by **repurposing WD's two empty Promin bays**. The Promin has three module bays
(`map`, `conn`, `side`); WD's own `conn` and `side` modules are functionally empty (no
pages/sensors/effects — only `map` does anything), so this component replaces those two
`MODULES` entries with the antenna (`conn` bay) and the process module (`side` bay). The
Promin still has exactly three bays, so **nothing in WD's customize UI changes** — no new
cells, no XML override.

Why not just add new bays? Because WD's customize UI builds one fixed cell per bay and only
ships XML for three — a fourth bay is a fatal `XML node module_open_4 not found`. Reusing
the two empty bays avoids that entirely. Trade-offs: WD's (do-nothing) `conn`/`side`
module items become non-installable, and the reused bays render WD's placeholder null mesh
on the Promin.

## Placeholder art

This component ships **no bespoke art or models**; the tier *logic* is complete, but:

- **Item icons**: all three item types have their own generated 50×50 icons —
  `icon_ii_wd_antenna.dds` (mast + broadcast waves), `icon_ii_wd_process.dds` (an IC
  chip), and `icon_ii_wd_scanner.dds` (a radar scan display). `icon_ii_wd_null.dds`
  remains as the base fallback.
- **Scanner is invisible**: it attaches no worn model on purpose (reusing a mesh showed a
  duplicate bracer on the arm). It's a logical device — worn state + tier only. To ship a
  real model later, re-enable the attach in `d_ii_scanner.sync_attachment` (a commented
  template is there) and tune the transforms in `d_ii_scanner_config.script`.

## Not verified in-game

All Lua compiles (Lua 5.1 `luac`), formats (StyLua), and passes the language server, and
all XML validates — but the WD device/slot integration **could not be exercised in game**
during development. It follows WD's own patterns (`d_vektor`, `d_bracer`) faithfully but
may need iteration. In particular verify: the scanner mounts on the bracer and reports its
tier; carrying the antenna + a process module with the Promin worn is detected; and
identification switches to the tier behaviour with the full kit. WD is coupled by
section/table names — if WD updates its device/slot internals, this component may need
matching updates.
