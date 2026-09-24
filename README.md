# Immersive Identification

A S.T.A.L.K.E.R. Anomaly / GAMMA mod: aim at an NPC or creature and press a
bindable key to identify them. Instead of a HUD element, the result is a
floating card anchored to the target's own body in 3D world space — a small
rotating spinner on their body while it "scans", then a card fades in off to
one side, joined to a relation-coloured dot on their chest by a leader line:
a faction patch, their faction name and personal name stacked (relation-
tinted header, brighter name), and their rank on its own line underneath
(skipped for monsters/mutants, which don't have one).

Built for the engine exposed by this repo (`xray-monolith`) and modelled on
the card/leader-line technique used by
Immersive Quest Markers

## Install

### Mod Organizer 2 (FOMOD)

`immersive-identification-fomod-v<version>.zip` (built from `fomod/` +
`gamedata/` in this repo) is a ready-to-install FOMOD archive:

1. In MO2: **Install Mod...** and point it at the zip (or drag it into the
   MO2 window).
2. Two optional components in the wizard, both unchecked by default:
   - **Neutralize FactionID HUD** — if you also have the separate
     **FactionID** mod installed, check this so its own on-screen faction
     indicator doesn't show up alongside this mod's.
   - **Skill System: Perception** — if you also have the **Skill System**
     mod installed, check this to add a "perception" skill to it and link it
     to identification speed (see Perception skill integration below).
   Leave either unchecked if you don't have the corresponding mod; everything
   else installs with no other choices to make.
3. Enable it in your mod list like any other mod.

To rebuild the zip after editing the mod (from this directory):

```
nix run .#package   # builds immersive-identification-fomod-v<version>.zip
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
3. A small spinner rotates on their body for a moment, then a card fades in
   off to one side, joined to a relation-coloured dot on their chest by a
   leader line — faction patch, faction name, personal name, rank — holds
   for a few seconds, and fades out.
4. Re-pressing the key on an already-identified target restarts the reveal.
   Up to 5 identifications can be active at once (oldest is dropped first).

Two UI styles are selectable in MCM: **Card** (the default, described above)
and **Minimal** — just a faction-coloured dot with a small relation sign next
to it (`-` red for hostile, `+` green for friendly, `o` tan for neutral), no
card at all.

The card's overall size is a flat multiplier you set in MCM (not
distance-based — text stays a fixed size regardless, so this only scales the
plate/icon/dot/line around it). Below a configurable cutoff, the card layout
stops making sense (illegible text, a sliver of a plate), so it's replaced
with just the relation-coloured dot beside the target instead of trying to
cram the full card into too little space.

Everything is configurable in MCM: enable/disable, the key + modifier, UI
style, relation colouring, scan/fade/hold durations, max/fade-out range, the
target-assist radius (pixels, plus a line-of-sight toggle), card scale, and
binocular mode.

Raising binoculars always makes identification faster and extends its range
(default: ~2.5x range, reveals in ~40% of the normal time) — this applies
with the regular key too, independent of Binocular mode below. Toggle it and
tune both multipliers in MCM.

Farther targets also take longer to scan by default (up to 5x right at your
max range), scaling smoothly from instant up close — and since binoculars
extend that max range, the same physical distance reads as proportionally
closer through them, on top of their own flat speed bonus above. Toggle and
tune in MCM.

Higher-ranked stalkers also take longer to identify: a rookie always
identifies at the normal rate, and each rank above that has its own fixed
penalty (not an even step per rank — the jump from novice to trainee barely
changes the time, while expert/master/legend are noticeably slower), up to
3x by default for a legend. Monsters/mutants (no rank) are never penalised.
Toggle and tune the legend-rank ceiling in MCM.

Rain, storms, and fog can also slow identification. Fog scales with the
target's distance, while rain and storm wind apply only when you are exposed.
With Anomaly/GAMMA's gas-mask droplet state available, water collected on the
visor joins the same visibility penalty and mask wiping clears it naturally.
The strongest obstruction sets one capped slowdown, so related rain effects
are not multiplied together. Toggle and tune these options in MCM.

Combat also slows identification. The normal combat multiplier applies while
enemies are actively fighting the player and briefly after aggro drops. A direct
combat hit or hostile bullet passing nearby temporarily replaces it with a stronger
under-fire multiplier. Both multipliers, the pressure duration, and near-miss radius
are configurable in MCM.

Once you've identified a stalker, identifying them again later is faster
(default: 40% faster) — the mod remembers everyone you've identified,
including across save/load. Toggle and tune the speed multiplier in MCM.

### Binocular mode

Turn this on in MCM to add a second way to identify, alongside the normal
key: while actively looking through raised binoculars (not just holding them
— has to be zoomed in), aiming near a target and holding the aim steady for
a moment (configurable, default 0.6s) identifies them automatically, no key
press needed. Move the aim off them (or past the steady tolerance) to reset;
holding steady on them again re-triggers it. The key itself always keeps
working too, binoculars or not — unless you separately turn on "Require
binoculars", which restricts the key (and the auto-trigger) to only work
while actively looking through raised binoculars.

### Perception skill integration

If you have the **Skill System** mod (`haru_skills`) installed and check the
optional "Skill System: Perception" component when installing, identifying
targets gets faster the higher your perception skill level, and the first
time you identify a given stalker grants it a little XP — the same "skill
grows from using it" pattern the Skill System's own skills follow. Looting a
corpse you'd already identified grants a further bonus XP, once per corpse.
Each reward only pays out once per target, ever (including across save/load),
so re-identifying or re-looting doesn't farm repeat XP. It shows up as a real
named entry ("Perception", with its own icon) in the Skill System's own skill
menu alongside Strength/Endurance/Survival/Scavenging, not just a hidden
number. Toggle it and tune the speed bonus per level / XP per identify / XP
per loot in MCM, under "Skill System (Perception)". No effect (and no XP
grind) without both the Skill System mod and this component installed.

## Add your own UI style

Other mods can register their own tag style through this mod's `ii_api` global — it then appears
in the **UI style** dropdown alongside the built-in ones, and this mod keeps doing target
acquisition, line of sight, range and relation gating, scan timing and slot management for it:

```lua
function on_game_start()
    ii_api.register_style({ id = "my_bar", on_draw = my_draw, dist_scale = true })
end
```

- **[MODDERS.md](./MODDERS.md)** — the guide: hooks, the render record, widgets, the gotchas.
- **[examples/](./examples)** — two complete, installable example add-ons.

Want your own faction patch art instead of the game's icons? Switch on **Custom faction patches**
(UI Style / General) and register `ii_patch_<faction>` texture ids — see
[examples/custom_faction_patches](./examples/custom_faction_patches). The installer offers three
mutually exclusive sources: bundled **HD Faction Patches** artwork, **GRIP Patches**, or
**GAMMA Patches**.

Nothing in this mod needs editing or overwriting.

## Development

`nix develop` gives you `xmllint`, `lua-language-server`, Lua 5.1
(`lua`/`luac`), and `7z` on `PATH`. `types/` has EmmyLua stubs for the engine
API this mod uses (each entry cited against xray-monolith's C++ source), and
`.luarc.json` wires them up — point your editor's Lua LSP at this repo and
`gamedata/scripts/*.script` gets real completion/type-checking.

```
nix run .#check-xml                 # validate every XML file in the repo
nix run .#check-lua                 # full lua-language-server diagnostics, headless
nix run .#package                   # build immersive-identification-fomod-v<version>.zip
luac -p gamedata/scripts/*.script   # Lua 5.1 syntax check
```
