# Wearable Devices Compatibility — Feature Set

What the **st-wearable-devices (WD)** compatibility component currently brings to
**Immersive Identification**. Optional FOMOD component; install only alongside both mods.
It turns identification into a diegetic, gear-gated system built out of Promin modules and
a worn scanner, with a tier progression and a dedicated Promin readout screen.

---

## 1. Two identification channels

You build one of two channels; they are **mutually exclusive** (the antenna and the OSD
scanner share the Promin's `conn` bay, so only one can be installed at a time — that shared
bay *is* the AR↔OSD switch).

| | **AR channel** | **OSD channel** |
|---|---|---|
| Where results show | **On entities** — the usual floating tags / bodycam overlays | **Only on the Promin IDENTIFICATION page** — no on-entity UI at all |
| Scanner form | **AR Scanner** — a worn bracer device | **OSD Scanner Module** — a Promin module |
| Requires | antenna + process module (Promin) **+ worn AR scanner + bracer** | OSD scanner module + process module **only** (no antenna, no bracer, no worn device) |
| Promin worn & powered | yes | yes |

Face redaction (the censor-over-faces feature) is independent of the scanner channel.

---

## 2. Items (10)

All installed/removed through WD's own systems and shown in the bracer customize screen.

**Promin modules** (install via the item use-menu or the customize screen; consumed on
install, returned on removal):

| Item | Bay | Cost |
|---|---|---|
| Promin Antenna Module | `conn` | 4 500 |
| Promin Process Module — Tier 1 / 2 / 3 | `side` | 5 000 / 9 000 / 16 000 |
| OSD Scanner Module — Tier 1 / 2 / 3 | `conn` (shares w/ antenna) | 7 000 / 13 000 / 22 000 |

**Worn device** (mounts on the bracer via its own logical slot):

| Item | Cost |
|---|---|
| AR Scanner — Tier 1 / 2 / 3 | 7 000 / 13 000 / 22 000 |

Only one module fits per bay: installing a different process tier (or swapping antenna ↔
OSD scanner) **evicts** the current occupant and returns it to your pack.

---

## 3. Tier progression

**Process module** — sets scan speed and progressively unlocks *what data* is shown:

| Process tier | Base scan time | Unlocks (cumulative) |
|---|---|---|
| Tier 1 | ~1.5 s | Faction, Distance |
| Tier 2 | ~1.0 s | + Relationship, + Rank |
| Tier 3 | ~0.5 s | + Weapon & caliber |

**Scanner** (AR or OSD, same tier behaviour) — sets *range and capability*:

| Scanner tier | Identify range | Unlocks |
|---|---|---|
| Tier 1 | 10 m | — |
| Tier 2 | 20 m | Scope / ADS support, magnification range boost |
| Tier 3 | 30 m | + No darkness scan-time penalty |

With the kit assembled, these tiers **drive** identification and override the matching
base-mod settings (most scan-time modifiers, range, night penalty, ADS enablement, and per-field
display gates). Combat pressure and weather visibility still modify the fixed process-tier scan time.
`wd_require_kit` (default on) blocks identification entirely without the kit; turn it off to keep
normal identification and let the kit only *enhance* it.

---

## 4. Promin IDENTIFICATION screen

Installing an OSD scanner module adds a third page to the Promin screen — **IDENTIFICATION**
— cycled with BIOMONITOR / NAVIGATION (double-tap the Promin key). It mirrors the NAVIGATION
layout: the biomonitor stays on the left, and the **last-identified target** fills the right
panel (where the map normally is):

- **Portrait** of the target (its `character_icon`)
- **Name, Faction, Rank, Position, Distance, Weapon & caliber**
- Fields the current process tier hasn't unlocked show `---` (same gating as the on-entity
  tags); monsters have no portrait, so it's hidden for them.

Because the Promin CRT screen has no font (WD renders numbers as pre-baked digit textures),
the component ships a **monospace glyph atlas** + a text compositor that draws arbitrary
strings by binding per-character glyph textures onto slot widgets — the same technique WD
uses for its clock, extended to the full alphabet.

---

## 5. MCM — "Wearable Devices" page

Every tier value is tunable on the Wearable Devices page of the Immersive Identification MCM:

- **Require Scanner kit to identify** (master gate)
- **Process scan times** — Tier 1 / 2 / 3
- **Scanner ranges** — Tier 1 / 2 / 3
- **Feature-unlock tiers** — which process tier reveals Faction / Distance / Relationship /
  Rank / Weapon
- **Scanner capability tiers** — which scanner tier unlocks ADS support / magnification boost
  / no-night-penalty

The rest of the Immersive Identification MCM (UI style, colours, keybind, …) applies as usual.

---

## 6. Crafting

Recipes for all 10 items, mirroring WD's own recipe format. Tool-tier gated:

- **Tier 1** items (and the antenna) — **basic** tools
- **Tier 2** items — **advanced** tools
- **Tier 3** items — **expert** tools

Higher tiers consume the previous tier plus Promin tech (`wd_promin_upgrade_kit`) and common
electronic parts.

---

## 7. Art

Custom generated 50×50 inventory icons:

- **Antenna** — mast + broadcast waves
- **Process module** — IC chip
- **AR Scanner** — target silhouette in AR viewfinder brackets
- **OSD Scanner** — radar scan display

The AR scanner's *worn* model is intentionally **invisible** (a placeholder mesh showed a
duplicate bracer on the arm); it's a logical device — worn state + tier only.

---

## 8. Engineering / robustness

- **Non-invasive:** every WD/base-mod call is `rawget`/`pcall`-guarded, so the component is
  inert (returns "not driving") when WD or Immersive Identification is absent, and never
  throws into the per-frame identify path.
- **Tier seam:** drives the base mod through a single `ii_identify.tier_provider` hook,
  snapshotted once per frame; the driver's WD-state read is cached (~250 ms).
- **No new Promin bays / no customize-UI crash:** repurposes WD's two functionally-empty
  bays (`conn`, `side`) instead of adding bays (a 4th bay is a fatal `module_open_4` XML
  crash). The Promin keeps exactly three cells.
- **Ident page:** a VFS override of WD's `d_promin_ui.script` (verbatim copy + two marked
  `II-COMPAT` additions), since WD's page-builder table has no registration seam. Re-sync if
  WD updates that file.

---

## 9. Fixes since first cut

- Modules now install/appear correctly in the Promin (a dead `actor_on_first_update`
  callback previously stopped registration).
- OSD scanner converted from a worn item to a **Promin module**; the OSD channel no longer
  requires the antenna (only the OSD module + a process module).
- AR scanner worn model made invisible (was spawning a duplicate bracer).
- Item descriptions: fixed the missing line break after **FEATURES:** (an engine text-parser
  quirk dropped a `\n` placed right after a colour tag).
- **Require Scanner kit** toggle: disabling it no longer blocks identification (the checkbox
  marshalled as the number `0`, which is truthy in Lua; now coerced to a real boolean).
- Distinct AR-scanner icon added; OSD scanner keeps the radar icon.

---

## Status / caveats

The tier **logic** is complete and statically validated (Lua 5.1 `luac`, StyLua, the language
server, and XML all pass). The WD **device/slot integration** could not be exercised in-game
during development — it follows WD's own patterns faithfully but may need iteration, and the
Promin ident page's on-screen layout constants will likely need in-game tuning. WD is coupled
by section/table names; a WD update to its device/slot/module internals may require matching
changes here.
