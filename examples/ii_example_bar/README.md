# Example Bar

The minimum viable Immersive Identification UI style: a faction-coloured bar under each
identified target, with a thinner rank-coloured bar beneath it.


```
          (target's head)
        ────────────────      <- faction / relationship colour
        ────────────────      <- rank colour (hidden if "Show rank" is off)
```

## Files

```
gamedata/scripts/ii_example_bar.script            the style
gamedata/configs/text/eng/st_ii_example_bar.xml   the MCM dropdown label
gamedata/configs/text/rus/st_ii_example_bar.xml   ...in Russian (windows-1251)
```

That is the entire mod. Nothing from Immersive Identification is edited or overwritten.

## What it demonstrates

- **Registering** from `on_game_start` (never a script's top level — load order is undefined)
  and staying inert when the host mod is absent.
- **The three hooks**: `on_create` makes widgets once per tag slot, `on_draw` positions them
  every frame, `on_hide` hides them so they do not linger on screen.
- **Reusing the host mod's widget templates** through `ctx.xml`, so there is no XML or texture
  to ship.
- **Honouring the player's settings** without extra work: `a.scale` carries their *Card scale*,
  `a.a` carries the fade curve, `a.rank` is `nil` when *Show rank* is off, and `a.sign` is `nil`
  when *Show relation* is off (it falls back to the faction colour).
- **Aspect correction** — widths multiplied by `ctx.config._ui_kx`, heights not.
- **`dist_scale = true`**, so the bar shrinks with distance like the Minimal and Simple styles.

## Install

Copy `gamedata/` into a new mod folder, enable it below Immersive Identification, then pick
**Example Bar** in MCM → Immersive Identification → UI Style → General → UI style.

See [MODDERS.md](../../MODDERS.md) for the full guide.
