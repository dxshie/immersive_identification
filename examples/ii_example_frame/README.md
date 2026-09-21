# Example Frame

A four-strip outline rectangle locked to the target's head — or full body, following the
player's *Bodycam box area* setting — with the target's name beside it.

```
        ┌──────────┐  Petrukha
        │  (head)  │
        └──────────┘
```

## Files

```
gamedata/scripts/ii_example_frame.script            the style
gamedata/configs/ui/ii_example_frame.xml            its own widget templates
gamedata/configs/text/eng/st_ii_example_frame.xml   the MCM dropdown label
gamedata/configs/text/rus/st_ii_example_frame.xml   ...in Russian (windows-1251)
```

## What it demonstrates

Everything [ii_example_bar](../ii_example_bar) does, plus:

- **`want_box = true`** — the target's projected box centre and half-extents (`a.box_cx`,
  `a.box_cy`, `a.box_hw`, `a.box_hh`). Drawing code cannot derive these itself; it has no world
  access. They are `nil` whenever the target does not project this frame, which the code checks
  before every use.
- **Shipping your own widget XML** rather than reusing the host mod's templates — including the
  `stretch="1"` requirement, which is load-bearing (see the comment in the XML).
- **Text widgets** and their drop-shadow twins, via `ctx.draw_shadowed_text`.
- **Caching**: the XML is parsed once for the session rather than once per tag slot, and
  `ctx.set_text` skips the native call when the string has not changed.
- **Not** setting `dist_scale`: the box extents come from a world projection, so the frame
  already shrinks with distance. Scaling it again would compound.

It reuses the `ii_white` texture that Immersive Identification registers, so there is no `.dds`
to ship. Your own art goes in `gamedata/textures/` with a registration XML in
`gamedata/configs/ui/textures_descr/`.

## Install

Copy `gamedata/` into a new mod folder, enable it below Immersive Identification, then pick
**Example Frame** in MCM → Immersive Identification → UI Style → General → UI style.

See [MODDERS.md](../../MODDERS.md) for the full guide.
