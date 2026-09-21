# Changelog

## Unreleased

- **Tags now clear when the target falls outside your identify range.** Previously each tag kept
  the range it was identified at for its whole life, so losing magnification -- lowering a scope
  or binoculars, which cuts the effective range by the entire zoom factor -- left distant tags
  floating on targets you could no longer identify at all. The check now runs every frame against
  the live range, so it also covers you or the target simply walking apart. What stays tagged is
  exactly what you could re-identify right now.
  **This ends the old binocular linger for distant targets** -- glassing someone at 200 m and
  lowering the binoculars now drops that tag instead of keeping it readable.
- **New option: Clear tags when lowering binoculars** (Binoculars, off by default). Wipes every
  identified target when you stop looking through them, including ones still inside your normal
  range -- distant ones already go on their own now (above). On, glassing becomes strictly live
  observation: what you saw through the optic is gone as soon as it leaves your eyes.
- **Neutralize FactionID HUD is now pre-selected in the installer.** It is marked Recommended
  rather than Optional, so it installs unless you uncheck it -- virtually every setup that
  wants this mod already has FactionID, and leaving both on gives you two faction indicators
  at once. It is inert if you don't have FactionID, and unchecking it keeps FactionID's HUD.
- **New option: Scale assist radius with zoom** (Targeting, on by default). The target-assist
  radius now shrinks by however much your optic magnifies, so the assist forgives the same
  amount of *real-world* aim error scoped as unscoped. A fixed pixel radius was never a fixed
  amount of help: at 4x the same 35 px covers a four-times-wider slice of the world, so scoping
  in quietly made the assist grabbier exactly where you were aiming most carefully. It stays
  usable at high zoom because the silhouette it measures from grows as the radius shrinks, and
  it is floored so even a binocular can't reduce it to "direct hit only". Turn it off for the
  old flat-radius behaviour. The debug ring and its label show the effective radius.
- **Patch style tuning.** The outline thickness slider now goes down to **0** (no ring at all,
  just the bare faction patch -- and it no longer pads the layout when off). Default patch
  size is now **13** (was 22) and the default outline gap **0** (was 3), for a tighter marker
  out of the box.
- **New option: Show relation** (UI Style -> General). Turns the whole enemy/friend/neutral
  cue on or off, so a tag can tell you *who* someone is without telling you how they feel
  about you. Every style respects it: Minimal drops its -/+/o sign, Simple 2 drops its
  triangle (and the row closes up around the circle), the Card and Simple lose their relation
  tint, Patch's ring goes neutral, and Bodycam / Minimal 2 -- whose only cue *is* the relation
  colour -- fall back to the faction colour rather than rendering a marker that says nothing.
- **Colour by relation** no longer doubles as the Minimal sign toggle. It is now purely about
  colour; use the new **Show relation** to hide the cue itself. If you were turning
  **Colour by relation** off to hide Minimal's sign, turn off **Show relation** instead.
- **Card options moved to their own MCM page.** **Card scale** and **Mini mode cutoff** now
  live under **UI Style -> Card** instead of cluttering **UI Style -> General**. Because an
  option's storage path follows its page, **both reset to their defaults** (1.00 and 0.40) --
  set them again if you had them tuned. Card scale's tooltip now admits what it always did:
  despite the name it scales *every* style, not just the Card.
- **New UI style: Patch.** The faction patch on its own, ringed by a relationship-coloured
  outline (red enemy / green friendly / tan neutral) -- who they are plus friend-or-foe, with
  no text and no dot. It scales with distance and zoom like Minimal / Simple, so the patch,
  the ring and the gap between them keep their proportions at any range. New **UI Style ->
  Patch** MCM page: patch size, outline thickness, and outline gap. Turning off **Show
  faction** leaves the bare ring as a locator.
- **No identification while you're reading the PDA.** Focusing the PDA -- right-click,
  left-click or R to raise the 3D PDA to your face, or the fullscreen PDA window with 3D PDA
  off -- blocks every identification path (keypress, auto-identify, and the hipfire / ADS /
  binocular auto-triggers) and disarms the dwell timers, so unzooming doesn't instantly reveal
  whatever you happen to be facing. Merely holding the device out, screen lowered, still
  identifies. Raising it also CLEARS the tags already on screen -- they are not left pinned to a
  world you are not looking at -- so lowering the PDA re-scans from scratch (fast for anyone you'd
  already identified, via the familiarity bonus).
- **Face redaction moved out of this mod.** The face-censoring post-process was never
  part of identification -- no aiming, no keypress, its own range and its own sweep --
  and its engine half already shipped in the **xray-monolith-bodycam** repo, so the
  Lua driver, MCM page and strings now live there too
  (`gamedata/scripts/bodycam_face_redaction.script`, settings under a new **Face
  Redaction** MCM page). The two are independent: each works with the other absent.
  Removed here: the **Face Redaction** page and every `redact_*` option, the
  **Redaction in scope** toggle on the PiP page, their preset entries, and the now-unused
  `bodycam_redaction.ps` shader. **If you used face redaction, enable it again in the
  new page** -- the old settings do not carry over.
- The **Crooks** preset now actually turns on **instant identify** and clears the
  per-mode instant exclusions (and sets scan time to 0), so hipfire, ADS, and binocular auto-identification
  all reveal immediately. It also turns on **Only show overlay while aimed**.
- The **Bodycam** preset resets the tag X/Y offsets to 0 and turns off
  **Only show overlay while aimed**.
- **Auto-identify visible targets** now identifies every target in your view and in range
  without aiming. It no longer depends on **Identify all in assist radius** (which only
  governs the hipfire / ADS / binocular auto-triggers), and it skips targets behind the
  camera so they can't fill the tag slots.
- The **Debug draw** FOV ring is now a real circle -- one anti-aliased `ii_ring`
  outline stretched to `fov_radius` -- instead of 32 separate dots, so it reads cleanly
  at any radius and leaves the whole dot pool for target bones.
- Split configuration, frame caching, geometric visibility, tracking, and widget
  rendering into focused scripts while keeping `ii_identify`'s public interface.
- Continuous tag refreshes skip scan-penalty calculations. Acquisition rejects
  ineligible/out-of-radius candidates before LOS; geometry and aim-mode queries
  are reused within each update, without adding visibility delay.
- Targets retain stable widget slots. Automatic scene sweeps fill available slots
  without repeatedly evicting active scans in crowds; direct aiming can still replace
  an older target. Card measurements, text, visibility, and rounded distance labels
  update only when needed, and suppressed HUD modes skip unused layout work.
- Missing humanoid bones are checked by ID before sampling, allowing the intended
  creature anchor fallbacks instead of silently accepting the model's root bone.
- Fixed distance scaling for **Minimal**, **Minimal 2**, **Simple**, and **Simple 2**
  marker graphics: sizes now follow camera depth and zoom, continue shrinking beyond
  50 metres, and retain fractional pixels. Removed the downward distance nudge and
  made configured offsets follow the same projection. A near-camera size cap remains.
  Simple's name no longer shifts its graphical marker away from the entity; native
  text sizes are unchanged. Minimal still honours its distance-scaling toggle.
- New **"Anchor position"** setting (UI Style → General): choose where the tag / marker is drawn on
  the target — **Head** (default), **Torso**, or **Feet**. Applies to the card and every dot style
  (and the in-scope scope marker); the Bodycam box keeps its own Head/Body setting.
- New **"Minimal 2"** UI style: the most stripped-down marker — a single bare **dot with no glow**,
  coloured purely by **relationship** (red enemy / green friend / tan neutral). No sign, no text.
- **Reverted the depth-aware Bodycam text** rendering — the name / faction / weapon lines now
  always draw as flat CUIStatic text (like the box already did), instead of the engine
  glyph-emitter overlay that occluded them behind walls / the viewmodel. (Mod side; the matching
  engine glyph pass is being removed separately.)
- New **"Identify all in assist radius"** toggle (Targeting, on by default): automatic
  identification (Auto-identify + the hipfire / ADS / binocular auto-triggers) reveals **every**
  eligible target inside the target-assist radius, so a cluster of stacked stalkers is identified
  at once. Turn it **off** to identify only the single target nearest your aim. (A manual keypress
  always identifies the nearest.)
- **Minimal style** — its two elements are now individually toggleable, reusing the existing
  content toggles: the **faction dot** follows **Show faction**, the **relation sign** follows
  **Colour by relation**. Turning both off leaves a neutral locator dot so the tag never vanishes.
- New **"Exclude hostiles in combat"** toggle (Targeting, off by default): an entity that is
  actively hostile toward you and aware of you (pulled aggro / will attack) is never chosen as an
  identification target — the assist skips it and no path can identify it. A target identified
  *before* combat that then turns hostile has its tag **dropped immediately** the moment you engage
  it. Detected from its AI combat target and its enemy relation + line of sight to you.
- **Debug draw** gained an **identify tracer + performance readout** in the info panel: a **CPS**
  (cycles/sec) counter and per-cycle mod-loop time; the enabled auto-triggers; the **last
  identification** (what triggered it, target, when, scan time); and a live **"gate"** line that
  explains why the aimed candidate is or isn't being identified (out of range, no LOS, hostile,
  already identified, eligible, …).

## 3.3.0 — everything since 3.2.0

Foliage/cover control for line of sight, built on 3.2.0's LOS overhaul. Russian translation kept
in full parity.

### See-through geometry: block or penalise
The 3.2.0 LOS rewrite made identification see *through* transparent surfaces (fences, glass, and
the wide invisible clip meshes that were false-blocking). 3.3.0 adds opt-in control over that,
using the ray-hit material's transparency factor + name (all off by default):

- **"Block ID through transparent surfaces"** (Targeting) — treat every see-through surface
  (chain-link fences, glass, foliage, invisible **clip brushes/meshes**) as solid, so you cannot
  identify a target through them. Uses the exact material transparency, not guesswork.
- **"Block ID through foliage"** (Targeting) — the lighter variant: only **foliage** blocks
  (bushes / trees / grass, matched by material name — verified against GAMMA's `bush`, `bush_sux`,
  `grass`, `tree_trunk`), while fences and glass stay see-through.
- **"Foliage Penalty"** (Scan Time) — the *soft* alternative: instead of blocking, identifying a
  target **through foliage takes longer** (flat `foliage_penalty_max` multiplier, default 2.5×),
  slotted into the scan-time chain next to the distance/rank/weight/night penalties.

When a block is on, the direct-mesh-hit LOS shortcut is bypassed so the block is actually enforced
(the mesh pick sees through those surfaces). Foliage recognition is shared across all three
features, so they classify plants identically.

### Debug
- Debug draw's info panel now shows the **`front:` material name + transparency** of the first
  surface between the camera and the aimed target — for tuning the foliage material list.

### Tuning
- **"Base identification distance"** slider max lowered **500 → 250 m** (default 50 unchanged).

## 3.2.0 — everything since 3.1.0

Focused on **line-of-sight reliability**, **snappier auto-identification**, and tidying up the
range/penalty model. Russian translation kept in full parity throughout.

### Line-of-sight overhaul (fixes "I clearly see the target but LOS says no")
- **Geometry is now the LOS authority.** Dropped the `db.actor:see()` gate — that's the actor's
  **AI vision** (a visual-memory lookup limited by vision *range*, an *FOV cone*, and target
  *luminosity*, driven by the AI head, not your camera), which false-negated on exactly this
  mod's cases: a distant target you're scoping/glassing, a peripheral one, or one in shadow —
  all clearly on your screen. LOS is now: a clear geometric ray from the render camera, **or** a
  direct crosshair mesh-hit. (Night is a scan-time penalty, not a visibility block.)
- **Transparency-aware occlusion.** The LOS raycast now marches through **see-through** materials
  (chain-link fences, foliage, glass, and the wider invisible **clip meshes**) instead of
  stopping at the first collision — only an **opaque** surface blocks. This was the main cause of
  a clearly-visible target reading as occluded.
- **A direct mesh-hit counts as clear LOS** — the aim ray already proved a clear line to the
  target's model, so the body-sample check is skipped for the aimed target.
- **Better body sampling for peeks.** Added head + shoulder sample points (using the real head
  bone, not a lifted anchor that could clip into a ceiling), so a target peeking with just its
  head/shoulder over cover is detected. The "behind a wall" guard is fully intact.

### Identification behaviour
- **Snappy auto-identify.** The target under your crosshair now identifies **immediately** (the
  full-scene sweep stays throttled), removing the up-to-250 ms delay before a scan even started.
- **"Only show overlay while aimed" is now a list-membership gate** (not a display gate): aiming
  away **drops** the target, so aiming back re-runs the **whole scan** rather than reappearing
  instantly. Auto-identify is aim-scoped while it's on.
- **Re-look re-scan.** After looking away and back, an already-identified target re-runs its scan
  instead of refreshing instantly.
- **New held-item weight penalty** (Scan Time page, off by default): the heavier the item in your
  hands, the longer identification takes — a heavy weapon is harder to hold steady enough to
  read a target. Tunable max slowdown + reference weight.

### Range model
- **Renamed "Max range" → "Base identification distance"** — it's the *base* that scales up
  (magnification / boosts) or down (penalties), not a hard maximum. (Internal key unchanged, so
  saves/presets are unaffected.)
- **New per-mode "Max identification distance" hard-cutoff sliders** (Hipfire / ADS / Binoculars,
  5 m steps) that clamp the *effective* range after all scaling, so a high-magnification binocular
  (or any runaway scaling) can't reach absurdly far. 0 = no cap.
- **ADS range multiplier default is now 1.0** (was 1.6) — plain/iron-sight ADS no longer widens
  the range by itself; scope magnification still does (with zoom-scaling on).
- **Removed the tag fade-out-with-distance** — tags stay full-opacity up to the range cutoff.

### MCM & presets
- The three per-mode auto-trigger toggles (Hipfire / ADS / Binoculars) are renamed
  **"Auto Identification"**.
- New **"Default settings"** preset — resets every option to its default in one click (colours
  reset separately via the Colors page's "Custom colours" toggle).
- **Default FOV assist radius lowered 90 → 35** (tighter default assist).

### Debug
- New **bottom-right info panel** (Debug draw): every target currently inside the FOV radius
  (name / distance / in-range / LOS), plus the aim **mesh-hit** with a **see / ray / LOS**
  breakdown so you can tell exactly which check is (or isn't) gating.

### Fixes
- Fixed a **crash** (`draw_slot`, nil text width) when a target with no displayable text — e.g.
  a mutant — drew as a **Card** (surfaced by the Default preset selecting the Card style).

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
