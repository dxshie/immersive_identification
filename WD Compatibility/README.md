# Immersive Identification — st-wearable-devices Compatibility

Optional FOMOD component. Install **only** alongside both **Immersive Identification**
and **st-wearable-devices** (WD). It gates identification behind wearable scanner gear
and a module tier system. See `SPEC.md` §7.3 for the full design.

## What it adds

- **Promin Antenna Module** — establishes the scanner↔Promin link (required).
- **Promin Process Module (Tier 1/2/3)** — sets scan speed and gradually unlocks the
  data shown: faction + distance (T1), + relationship + rank (T2), + weapon (T3).
- **AR Scanner (Tier 1/2/3)** — a **worn** bracer device; identification is shown **on
  entities** the usual way (tags/overlays). Sets range (10/20/30 m) and unlocks scope/ADS
  support + a magnification range boost (T2) and no-night-penalty (T3). Needs the antenna
  + a process module in the Promin.
- **OSD Scanner Module (Tier 1/2/3)** — a **Promin module** (not worn); identification is
  shown **only on the Promin IDENTIFICATION page** — no on-entity UI at all (no tags, no
  in-scope markers). Same 3 tiers as the AR scanner. It sits in its own Promin bay (`ii_osd`,
  added by this component — see below), so it can be installed **alongside** the antenna.
  The OSD path needs **only the OSD scanner module + a process module** (no antenna, no worn
  scanner, no bracer). The AR and OSD channels are independent — with both installed you get
  entity overlays *and* the Promin readout. The Promin ident readout is the OSD channel
  (shows "install OSD scanner" without one). Face redaction is independent of the scanner.

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

This works by **repurposing WD's two empty Promin bays and adding a fourth**. The Promin
ships three module bays (`map`, `conn`, `side`); WD's own `conn` and `side` modules are
functionally empty, so this component replaces those two `MODULES` entries with the antenna
(`conn`) and the process module (`side`), and **adds a fourth bay** (`ii_osd`) for the OSD
scanner. So all four can be installed at once: map (WD) + antenna + OSD scanner + process.

The fourth bay needs a shipped **override of WD's `ui_wd_customize.xml`** — WD's customize
screen builds one cell per bay and only ships XML for three, so a fourth bay is otherwise a
fatal `XML node module_open_4 not found`. Our copy adds a 4th module cell. (Re-sync it if WD
updates that file.) Trade-offs: WD's do-nothing `conn`/`side` module items become
non-installable, and the extra bays render WD's placeholder null mesh on the Promin.

Because the antenna and OSD scanner now sit in separate bays, the **AR and OSD channels are
independent**: install both (plus a worn AR scanner) to get on-entity overlays *and* the
Promin readout at the same time.

## Identification notifications

While you're on the **BIOMONITOR** or **NAVIGATION** page and a target is identified, a
notification card pops up in the **bottom-right** and stacks upward as more come in (up to
four, expiring after a few seconds): faction emblem in the left circle, name + distance in
the middle, and rank as a level ("Rank 1"…"Rank 8", mapped from the rank name) on the right.
Nothing shows on the IDENTIFICATION page itself (the full readout is already there).
Rendered by `d_ii_promin_notify.script`; the layout constants (card size, anchor, per-field
positions) are at the top of that file for in-game tuning. The `d_promin_ui.script` override
eager-builds the biomonitor/navigation pages so the overlay draws on top of them.

## Promin IDENTIFICATION tab

Installing the antenna adds a third page to the Promin screen — **IDENTIFICATION**,
cycled with the other tabs (double-tap the Promin key, default). It mirrors the
NAVIGATION page's layout: the **biomonitor stays on the left**, and the
**last-identified target** is shown in the **right panel where the map normally is** — a
**portrait** (the NPC's `character_icon`) plus name, faction, rank, position, distance,
and weapon + caliber. Fields the current process tier hasn't unlocked show `---` (the
page respects the same tier gating as the on-screen tags); monsters have no portrait so
it's hidden for them.

The Promin's tab strip is **baked into the page background textures**. This component ships
a full three-tab strip (IDENTIFICATION / BIOMONITOR / NAVIGATION) baked into each page's
background, with the active tab highlighted:
- `ii_wd\ui\tablet_ui_main_ident.dds` — the IDENTIFICATION page's own background (our file).
- `wd\ui\promin\tablet_ui_main.dds` and `tablet_ui_main_map.dds` — **override** WD's
  biomonitor and navigation backgrounds so the third tab shows there too. (These replace
  WD's files at their own paths — re-export if WD updates that art.)

All three are DXT5 (matching WD's format) and use the author-provided art with WD's tab
font, so the strip reads natively on every page.

The Promin CRT screen has no font (WD renders numbers as pre-baked digit textures), so
this ships a **monospace glyph atlas** (`ii_wd_font.dds` + `ii_wd_font_textures.xml`,
one texture id per ASCII code) and a text compositor (`ii_wd_text.script`) that draws
strings by binding per-character glyph textures onto slot widgets — the same mechanism
as WD's clock, extended to the full alphabet. The page is a **VFS override of WD's
`d_promin_ui.script`** (its page-builder table is a file-local with no registration seam)
— a verbatim copy plus two marked `II-COMPAT` additions; **re-sync it if WD updates that
file**. Cosmetic limitation: WD's baked tab-label strip (BIOMONITOR / NAVIGATION) isn't
extended, so the tab is identified by the page's own "IDENTIFICATION" title rather than an
entry in that strip.

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
