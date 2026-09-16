---
name: spec-sync
description: Keep SPEC.md aligned with the Immersive Identification code. Invoke this WHENEVER you change runtime behaviour or configuration that SPEC.md documents — a config default in ii_identify.script's DEFAULTS, an MCM option/page in ii_mcm.script, a preset in presets_ii.ltx, or the logic of target selection / LOS / scan-time / boost_params / the UI styles / the state machine. SPEC.md is the source-of-truth design doc and drifts silently when code changes land without a matching spec edit.
---

# Spec sync (SPEC.md ⇄ code)

`SPEC.md` is the design source-of-truth. It goes stale whenever behaviour or config changes ship
without a matching edit — and a wrong spec is worse than none. After a code change, update the
section(s) that describe it. **Focus on correctness** (facts that are now wrong), not the
approximate `(line 1234)` anchors sprinkled through it — those drift constantly and chasing them
is low-value churn; leave them.

## What maps to what

| You changed… | Update SPEC section |
|---|---|
| `DEFAULTS` value / new config key (`ii_identify.script`) | **§4 Setting inventory** table (id, type, default, range, controls) |
| MCM option/page/nesting (`ii_mcm.script`) | §4 inventory + `MCM_PAGES` / page-list note; §3.5/3.5b if it's a mode option |
| A preset (`presets_ii.ltx`) | §4 (presets note) — and confirm every preset path resolves to a real page |
| Target selection / FOV assist / `get_target_obj` cascade | **§3.3 Target selection** |
| LOS: `has_los` / `has_clear_ray` / `tag_visible` | §3.3 (the `has_los` sub-block) |
| Scan-time factors (`*_scan_mult`, penalties, excludes) | **§3.4** factor table |
| `boost_params` return / binoc / ADS / range caps | §3.5, §3.5b (keep the return-tuple shape exact) |
| `tracked` entry fields / reveal state machine / re-identify rules | **§3.2 State machine** |
| A UI style (`draw_slot` branch, `draw_crooks`, `ui_style` values) | **§1** style list + **§3.6 UI rendering** |
| Free-aim / `aim_model_target` / `ETraceTarget` | §3.3 + **§10 Free-aim support** |
| WD compat tiers / items / Promin pages | **§7.3** + WD Compatibility/README.md |

## The setting inventory is the highest-drift part

§4's table must match **four** things at once — keep them in lockstep:

1. `DEFAULTS` in `ii_identify.script` (id + default value),
2. the `opt_*` calls in `ii_mcm.script` (type, range `(min,max,step,prec)`, which page),
3. `MCM_PAGES` in `ii_identify.script` (the page/sub-page path prefixes),
4. `presets_ii.ltx` (a preset writing a dead path silently does nothing).

Quick extraction to compare against the table:

```bash
# DEFAULTS keys + scalar values:
grep -nE '^\t[a-z_0-9]+ =' gamedata/scripts/ii_identify.script
# every MCM option and its page:
grep -nE 'page\("|opt_(check|track|list)\(' gamedata/scripts/ii_mcm.script
```

## Facts that MUST stay exact (they've been wrong before)

- **`boost_params` return tuple** — the arity/order (`binoc, ads, boosted, eff_max_dist,
  scan_mult`). Adding/removing a return value drifts every caller description.
- **`tracked` entry field list** in §3.2 (fields get added/removed, e.g. `last_seen_tg`; a
  removed one like `fade_dist` must leave the list).
- **`has_los` semantics** — whether/how `see()` gates, and the transparency-aware march. This is
  behaviour users feel; a stale description misleads debugging.
- **Default values and slider ranges** in §4 — the most-referenced numbers.
- **`ui_style` index → name** mapping (1 Card … 6 Crooks) in §1 and §3.6.

## Workflow

1. Land the code change.
2. Edit the mapped SPEC section(s); if it's a config change, reconcile §4 against all four sources
   above.
3. Sanity-read the section end to end — is anything else in it now false because of your change?
4. If it's user-facing, also add a `CHANGELOG.md` entry (and see `translation-sync` for strings).
