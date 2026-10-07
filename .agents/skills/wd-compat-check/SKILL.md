---
name: wd-compat-check
description: Check whether a (newly pulled) st-wearable-devices (WD) version is still compatible with Immersive Identification's "WD Compatibility" FOMOD component, and re-sync it if not. Invoke when the user pulls/updates st-wearable-devices, asks "is the new WD version compatible", or changes anything in "WD Compatibility/" that touches WD internals (d_promin*, d_bracer*, wd_* scripts, ui_wd_* XML, Promin textures). Optional arg: path to the WD checkout (default ~/code/lua/st-wearable-devices).
---

# WD compatibility check

The **WD Compatibility** component (`WD Compatibility/gamedata/`) couples to st-wearable-devices
in three ways, each of which breaks differently when WD updates:

1. **VFS overrides** — files at the *same path* as a WD file replace it (last-mod-wins). Today:
   `scripts/d_promin_ui.script`, `configs/ui/ui_wd_customize.xml`,
   `textures/wd/ui/promin/tablet_ui_main{,_map}.dds`. If WD changes its original, our stale copy
   silently reverts WD's change — and if WD's script starts needing a new XML node, our older XML
   is a **fatal crash** (`XML node <x> not found`). This is the most likely break.
2. **Script API** — calls into WD globals (`d_promin.*`, `d_promin_config.MODULES/BAYS/TIERS`,
   `d_bracer.is_worn`, `wd_slots.register_device`, `wd_worn.new`, `wd_screen.new_binder`,
   `d_promin_health_ui.build_chrome/build_bio/get_px/...`). Renames/removals → nil-call errors;
   **shape changes** (new required fields in a spec table, changed arg meaning) are not caught
   by any grep, only by reading the diff.
3. **Data assumptions** — e.g. `ii_wd_modules` repurposes WD's `conn`/`side` bays and appends an
   `ii_osd` bay; the customize XML has a hard-coded 4th module cell.

The synced WD version is recorded as `WD-SYNCED: <ver>` in the header of both text overrides
and is advertised to users in the FOMOD plugin name/description (`fomod/ModuleConfig.xml`).

## Procedure

1. Run the mechanical check (pass the WD path if not the default):
   ```
   .agents/skills/wd-compat-check/check.sh [~/code/lua/st-wearable-devices]
   ```
   It resolves the baseline commit from `WD-SYNCED`, lists WD commits since then, flags every
   override whose upstream changed, verifies every WD symbol our scripts reference (incl.
   `local X = rawget(_G, "d_...")` aliases) still exists, lists WD scripts we call into that
   changed, and runs `check-xml` + `luac -p`. Exit code = number of problem classes.
   - The "N upstream line(s) absent/altered" note is expected for intentional edits (e.g. the
     taller `cont_modules` in the customize XML) — review, don't panic.
2. **Read the WD diffs it lists** (`git -C <wd> diff <baseline> HEAD -- <file>`), focusing on
   the "changed" scripts and overrides. Look for: new XML node names a script now `InitStatic`s,
   changed `register_device`/`wd_worn.new` spec fields, changed `MODULES`/`BAYS` entry shapes,
   renamed page ids in `d_promin_ui`, new blacklists/registries our items should join (e.g.
   `mod_backpack_stash_wearables.ltx`).
3. **Re-sync each changed override** by replaying our additions onto the new upstream file —
   don't hand-merge:
   ```
   git -C <wd> show <baseline>:gamedata/<rel> > old; git -C <wd> show HEAD:gamedata/<rel> > new
   diff -u old "WD Compatibility/gamedata/<rel>" > ours.patch; patch new < ours.patch
   ```
   (use the scratchpad for temp files). Check the result keeps every `II-COMPAT` block /
   4th-cell addition and the header comment. Textures (`.dds`) can't be patched — if WD changed
   them, tell the user they need re-exporting with the 3-tab strip.
4. Bump the supported version to the WD `VERSION` everywhere it is stated: `WD-SYNCED: <ver>`
   in **both** override headers, and in `fomod/ModuleConfig.xml` both the plugin name
   `Wearable Devices Compatibility (WD <ver>)` and the `WD-SYNCED: <ver>` in its description
   (check.sh flags any mismatch). Then re-run
   `check.sh` until it exits 0, plus `nix run .#check-format` if any `.script` changed.
5. Report to the user: WD version checked, what broke and why (crash vs. silent revert vs.
   fine), what you re-synced, anything needing in-game verification or new art. Don't commit
   unless asked.
