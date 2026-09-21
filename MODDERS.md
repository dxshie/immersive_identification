# Writing your own Immersive Identification UI style

Immersive Identification does the hard part — deciding *who* the player has identified — and
then hands the drawing to a **UI style**. This guide shows you how to ship your own style as a
separate mod. You do not edit Immersive Identification, you do not overwrite any of its files,
and your style appears in its MCM dropdown next to the built-in ones.

If you only want to *use* the mod, you want [SPEC.md](./SPEC.md) §4 instead. If you want the
terse contract rather than a tutorial, that's [SPEC.md](./SPEC.md) §8.

**Contents**

1. [How it works](#1-how-it-works)
2. [A complete add-on in two files](#2-a-complete-add-on-in-two-files)
3. [The registration table](#3-the-registration-table)
4. [The three hooks](#4-the-three-hooks)
5. [`a` — the render record](#5-a--the-render-record)
6. [`ctx` — the toolbox](#6-ctx--the-toolbox)
7. [Making widgets](#7-making-widgets)
8. [Coordinates, scale and aspect ratio](#8-coordinates-scale-and-aspect-ratio)
9. [Respecting the player's settings](#9-respecting-the-players-settings)
10. [Performance rules](#10-performance-rules)
11. [Worked example: a bodycam-style outline](#11-worked-example-a-bodycam-style-outline)
12. [Debugging](#12-debugging)
13. [Gotchas](#13-gotchas)

---

## 1. How it works

Anomaly turns every `gamedata/scripts/<name>.script` into a global table named `<name>`. So
Immersive Identification's API object is simply the global **`ii_api`** — there is nothing to
require, import or patch.

You call `ii_api.register_style{...}` once with a table of callbacks. From then on:

- your style is an entry in the **UI style** dropdown on the mod's *UI Style → General* MCM page;
- when the player selects it, the mod calls **your** draw function for each identified target,
  every frame, instead of drawing one of its own styles.

Everything upstream of drawing stays the mod's job: aiming and target acquisition, the FOV
assist, line of sight, range limits, the scan timer and its multipliers, the "scanning" spinner,
fade in/out and hold timing, tag slot assignment, and hiding your widgets when the player
switches styles. You get a position on screen and the facts about the target, and you draw.

### Register from a function, not from your script's top level

At a script's top level there is **no guarantee `ii_api` has loaded yet** — two scripts' load
order is not defined. Register inside `on_game_start`, which runs after every script is loaded
but before MCM builds its menu and before the mod creates its tag widgets:

```lua
function on_game_start()
    ii_api.register_style({ ... })
end
```

If Immersive Identification is not installed at all, `ii_api` is nil. Guard it if your mod
should still work without it:

```lua
function on_game_start()
    if ii_api then
        ii_api.register_style({ ... })
    end
end
```

---

## 2. A complete add-on in two files

This is a whole working mod. It draws a faction-coloured bar under each identified target,
tinted by relationship when the player has that turned on.

**`gamedata/scripts/myid_bar.script`**

```lua
-- My Bar -- an Immersive Identification UI style.

local function on_create(state, ctx)
    -- One widget per tag slot, made once. Reuses a template from the host mod's XML;
    -- see section 7 for shipping your own.
    state.bar = ctx.xml:InitStatic("tag_s2_bar", ctx.parent)
end

local function on_draw(state, a, ctx)
    local kx = ctx.config._ui_kx                 -- aspect correction, see section 8
    local w = 30 * a.scale * kx
    local h = 4 * a.scale

    -- Relationship colour when the player wants it, faction colour otherwise.
    local col = a.sign and ctx.sign_colors[a.sign] or a.fcol

    state.bar:SetWndSize(ctx.size(w, h))
    state.bar:SetWndPos(ctx.position(a.hx - w / 2, a.hy + 10 * a.scale))
    state.bar:SetTextureColor(GetARGB(a.a, col[1], col[2], col[3]))
    ctx.show(state.bar, true)
end

local function on_hide(state, ctx)
    ctx.show(state.bar, false)
end

function on_game_start()
    if not ii_api then
        return
    end
    ii_api.register_style({
        id = "my_bar",
        on_create = on_create,
        on_draw = on_draw,
        on_hide = on_hide,
        dist_scale = true,   -- shrink with distance like the Minimal / Simple styles
    })
end
```

**`gamedata/configs/text/eng/st_myid_bar.xml`**

```xml
<?xml version="1.0" encoding="windows-1251"?>
<string_table>
    <string id="ii_uistyle_general_ui_style_lst_my_bar"><text>My Bar</text></string>
</string_table>
```

That string id is **not optional decoration**: it is how MCM finds the dropdown label for your
style. The format is `ii_uistyle_general_ui_style_lst_` + your `id`. Get it wrong and the
dropdown shows the raw id (`my_bar`) instead of a name. Ship a `rus/` copy too if you care about
Russian players — Anomaly string tables are **windows-1251**, not UTF-8.

Install it like any other Anomaly mod. Then: **MCM → Immersive Identification → UI Style →
General → UI style → My Bar**.

---

## 3. The registration table

```lua
ii_api.register_style({
    id         = "my_bar",   -- required
    on_draw    = fn,         -- required
    on_create  = fn,         -- optional
    on_hide    = fn,         -- optional
    dist_scale = false,      -- optional
    want_box   = false,      -- optional
})
```

| field | required | meaning |
|---|---|---|
| `id` | yes | Unique. Lowercase `a-z`, `0-9`, `_` only. Also the string-table suffix (section 2). Prefix it with something of your own (`myid_`) so two add-ons can't collide. |
| `on_draw` | yes | Called every frame for every visible identified target. |
| `on_create` | no | Called once per tag slot, lazily, immediately before that slot's first `on_draw`. Make widgets here. |
| `on_hide` | no | Called when a slot stops drawing. Hide your widgets here. |
| `dist_scale` | no | `true` makes `a.scale` follow camera depth and zoom (near = bigger, far = smaller) like the Minimal, Simple, Simple 2, Minimal 2 and Patch styles. `false` (default) gives the flat `card_scale` the Card and Bodycam styles use. |
| `want_box` | no | `true` also fills `a.box_cx` / `box_cy` / `box_hw` / `box_hh` with the target's projected head-or-body box. You cannot compute these yourself — drawing code has no world access. See section 11. |

Returns `true` on success, or `false, reason` if the table is malformed or the id is taken.
Nothing crashes if you ignore the result, but checking it while developing is cheap:

```lua
local ok, err = ii_api.register_style({ ... })
if not ok then printf("!![my_bar] %s", err) end
```

Other calls, if you need them: `ii_api.get(id)`, `ii_api.registered()` (array of every
registered style), `ii_api.count()`, and `ii_api.API_VERSION` (currently `1`; it only bumps if
an existing hook's contract *changes* — new optional fields don't bump it).

---

## 4. The three hooks

```lua
on_create(state, ctx, slot)
on_draw  (state, a, ctx, slot)
on_hide  (state, ctx, slot)
```

`state` is a plain table that belongs to you, one per tag slot. Keep your widgets and any cached
values in it. The mod never touches its contents.

`slot` is the tag slot index (1..N). You rarely need it — `state` is already per-slot — but it
is there for logging.

**The lifecycle.** The mod keeps a fixed pool of tag slots and assigns a target to one when it
is identified. The first time your style draws in a slot, `on_create` runs for that slot, then
`on_draw`. After that it is `on_draw` every frame for as long as that target is shown. When the
target is dropped — it died, went out of range or out of sight, the reveal timer expired, or the
player switched to another style — `on_hide` runs.

**`on_hide` is not optional in practice.** The engine's widgets stay on screen until something
hides them. If you create a widget and never hide it, it stays visible over the world forever.
If you make several, hide all of them.

**`on_draw` never sees a scanning target.** The mod draws its own rotating spinner during the
scan and only calls you once the target is revealed. You do not have to implement a scan state.

**Your code runs inside a `pcall`.** An error in your hook cannot take the HUD down with it. It
is logged once, and your style is then skipped *for that slot* for the rest of the session — so
a bug shows up as "my style stopped drawing", not as a crash. Check the log.

---

## 5. `a` — the render record

The second argument to `on_draw`. Reused between frames and between targets, so **read it, don't
keep it** — never stash `a` itself in `state`.

### Position and timing

| field | |
|---|---|
| `a.hx`, `a.hy` | Where to draw, in virtual pixels (section 8). The target's anchor point, already including the player's *UI offset X/Y* setting and their *Tag anchor* choice (head / torso / feet). |
| `a.a` | Alpha, `0`–`255`, already carrying the fade in/out and hold curve. Multiply your own opacity into it; never ignore it or your tag will pop instead of fade. |
| `a.scale` | Size multiplier. Always includes the player's *Card scale*; also includes distance scaling if you set `dist_scale` (capped near the camera, no floor far away). Multiply every pixel dimension by it. |
| `a.scanning` | Always `false` in `on_draw`. Present for completeness. |
| `a.stack_offset` | Vertical nudge the Card style uses to stop overlapping cards from landing on top of each other. Non-zero only for the Card style; ignore it. |

### Who the target is

| field | |
|---|---|
| `a.header` | Faction display name, e.g. `"Duty"`. `nil` when *Show faction* is off. |
| `a.name` | The target's name. `nil` when *Show name* is off. |
| `a.rank` | Rank label, e.g. `"Veteran"`. `nil` when *Show rank* is off, and for monsters. |
| `a.weap` | Held weapon + calibre. `nil` when *Show weapon* is off, and for the unarmed. |
| `a.icon` | Faction emblem **texture id**, e.g. `"dolg_icon"`. Feed it to `widget:InitTexture(...)`. |
| `a.sign` | `"-"` enemy, `"+"` friend, `"o"` neutral — **or `nil` when *Show relation* is off**. |

### Colours

Each is a `{ r, g, b }` table of 0–255 numbers. These are **shared, live tables** — the player
can retune every one of them on the MCM *Colors* page. Read the components, never hold or mutate
the table.

| field | |
|---|---|
| `a.fcol` | The target's faction colour. |
| `a.col` | Relationship-tinted colour, or a flat neutral when the player has *Colour by relation* off or *Show relation* off. |
| `a.rank_col` | Rank colour (novice grey → legend gold). |
| `ctx.sign_colors[a.sign]` | Red / green / tan, keyed by the relation sign. Guard `a.sign` for nil first. |
| `ctx.neutral` | The neutral fallback colour. |

### With `want_box = true`

`a.box_cx`, `a.box_cy` (centre) and `a.box_hw`, `a.box_hh` (half-extents), in virtual pixels,
around the target's head or full body per the player's *Bodycam box area* setting, and already
padded by their *Box padding*. **All four are `nil` when the target does not project this frame**
(off screen, behind the camera) — always check before using them.

---

## 6. `ctx` — the toolbox

The same table every frame.

| member | |
|---|---|
| `ctx.position(x, y)` | Makes a position for `SetWndPos`. **Returns shared scratch** — see the gotcha below. |
| `ctx.size(w, h)` | Makes a size for `SetWndSize`. Same warning. |
| `ctx.show(widget, bool)` | Show or hide. **Use this instead of `widget:Show()`** — it skips the native call when the state has not changed, which is a real per-frame saving. |
| `ctx.set_text(widget, str)` | Same idea for `SetText`. |
| `ctx.draw_shadowed_text(main, sh, x, y, alpha, r, g, b, shadow_a)` | Positions and tints a text widget plus its 1px drop-shadow twin, and shows both. |
| `ctx.xml` | The host mod's parsed `ii_tags.xml`, for reusing its widget templates (section 7). |
| `ctx.parent` | The window to parent your widgets to. |
| `ctx.config` | The **live** settings table. `ctx.config._ui_kx` is the aspect correction factor (section 8); every MCM option is in here under its own key. |
| `ctx.sign_colors`, `ctx.neutral` | See above. |
| `ctx.api_version` | `1`. |

> **`ctx.position` and `ctx.size` hand back a shared, reused object.** The next call overwrites
> the previous result. Use them *inline*, as the argument to the setter, and never store what
> they return:
>
> ```lua
> w:SetWndPos(ctx.position(x, y))          -- correct
> w:SetWndSize(ctx.size(a, b))             -- correct
>
> local p = ctx.position(x, y)             -- WRONG
> local s = ctx.size(a, b)                 -- p now holds the size, not the position
> w:SetWndPos(p)
> ```
>
> This is deliberate: it is what keeps the render path free of per-frame allocation.

---

## 7. Making widgets

Create every widget in `on_create` and only reposition it in `on_draw`. Creating widgets per
frame will destroy your framerate.

### Reusing the host mod's templates

`ctx.xml` is Immersive Identification's own parsed `ii_tags.xml`. Pulling a template from it
gives you a **new, independent widget** — you are not sharing the built-in styles' widgets.

```lua
state.icon = ctx.xml:InitStatic("tag_icon", ctx.parent)
```

Useful templates:

| template | what it is |
|---|---|
| `tag_icon` | Blank square for a faction emblem. Swap the texture with `InitTexture(a.icon)`. |
| `tag_node` | Round dot with a black outline ring baked in. |
| `tag_glow` | Soft round glow. |
| `tag_s2_circle` | Plain round dot. |
| `tag_s2_tri` | Triangle. |
| `tag_s2_bar`, `tag_accent`, `tag_line` | Plain rectangles (`ii_white`). `tag_line` can be rotated. |
| `tag_box_top` / `_bottom` / `_left` / `_right` | Thin strips for building an outline rectangle. |
| `tag_plate` | Filled rectangle for a background panel. |
| `tag_shadow` | Soft feathered drop shadow. |
| `tag_name:text`, `tag_head:text`, `tag_rank:text`, `tag_weap:text` | Text widgets (use `InitTextWnd`). Each has a `_sh` twin for the drop shadow. |

```lua
state.label   = ctx.xml:InitTextWnd("tag_name:text", ctx.parent)
state.shadow  = ctx.xml:InitTextWnd("tag_name_sh:text", ctx.parent)
-- later, in on_draw:
ctx.set_text(state.label, a.name)
ctx.set_text(state.shadow, a.name)
ctx.draw_shadowed_text(state.label, state.shadow, x, y, a.a, 235, 230, 220, 180)
```

**Creation order is draw order.** Whatever you create last draws on top.

### Shipping your own XML

For your own art or templates, ship an XML in `gamedata/configs/ui/` and parse it yourself:

```lua
local function on_create(state, ctx)
    if not state.xml then
        state.xml = CScriptXmlInit()
        state.xml:ParseFile("myid_bar.xml")
    end
    state.thing = state.xml:InitStatic("mybar_thing", ctx.parent)
end
```

Register any texture in `gamedata/configs/ui/textures_descr/`, the same way the host mod does.

> ### The `stretch="1"` trap
>
> **Every image widget you size from script must have `stretch="1"` in its XML.** `stretch="0"`
> is the engine's `tmNative` mode: it *silently ignores every `SetWndSize` call* and always draws
> the texture at its native pixel size. A 128×128 source then renders at 128×128 no matter what
> your code says. This has bitten this mod more than once — if your widget is enormous and
> ignoring your sizing, this is why.
>
> ```xml
> <mybar_thing width="12" height="12" stretch="1">
>     <texture r="255" g="255" b="255" a="255">ii_white</texture>
> </mybar_thing>
> ```

Textures the host mod already registers, free to reuse: `ii_white` (opaque square), `ii_dot`
(soft circle), `ii_node` (circle with outline), `ii_tri` (triangle), `ii_ring` (circle outline),
`ii_spinner`, `ii_shadow` (feathered).

---

## 8. Coordinates, scale and aspect ratio

Everything is in a fixed **1024 × 768 virtual space**, which the engine stretches to the real
resolution. You never deal in real pixels.

`a.hx`, `a.hy` is the anchor on the target's body. Smaller `y` is higher on screen, so to sit
*above* the anchor you subtract:

```lua
local y = a.hy - 20 * a.scale
```

Multiply every dimension by `a.scale`, and keep your layout centred on `a.hx` so it tracks the
target:

```lua
local w = 30 * a.scale
state.bar:SetWndPos(ctx.position(a.hx - w / 2, y))
```

### Aspect correction (`_ui_kx`)

The stretch from 1024×768 to the real screen is **not uniform** on a non-4:3 monitor. A widget
sized 12×12 comes out as an oval, not a circle. Multiply *widths* (never heights) by
`ctx.config._ui_kx`:

```lua
local kx = ctx.config._ui_kx
local d  = 12 * a.scale
state.dot:SetWndSize(ctx.size(d * kx, d))   -- stays round on 16:9 and 21:9
```

Read `_ui_kx` fresh each frame — the player can change resolution.

Two things need **no** correction: positions (`a.hx`/`a.hy` are already in the right space), and
the `want_box` extents (they come from a world projection that already accounts for it).

Do not aspect-correct a widget you also rotate with `SetHeading`. Rotation and non-uniform scale
do not commute, and a pre-squeezed shape comes out elliptical at every angle.

---

## 9. Respecting the player's settings

Your style will feel broken if it ignores the toggles the player already set.

**The content toggles come to you as `nil`.** *Show name*, *Show faction*, *Show rank*, *Show
weapon* and *Show relation* are folded in before `on_draw` — a field is simply absent when its
toggle is off. So checking presence *is* honouring the setting, and you get all five for free:

```lua
if a.name then
    -- draw the name
else
    ctx.show(state.label, false)   -- and hide it when it is off
end
```

The one that catches people is **`a.sign` is nil when *Show relation* is off**, which also
`nil`s `ctx.sign_colors[a.sign]`. Decide what your style does with no relationship to show. The
built-ins take two approaches: fall back to the faction colour when relation is the style's only
cue (Minimal 2, Bodycam), or just drop the element (Minimal's sign, Simple 2's triangle).

```lua
local col = a.sign and ctx.sign_colors[a.sign] or a.fcol
```

**Already handled for you**, with nothing to do on your side: *Card scale* and distance scaling
(both in `a.scale`), *UI offset X/Y* and *Tag anchor* (both in `a.hx`/`a.hy`), fade and hold
timing (in `a.a`), *Colour by relation* (in `a.col`), and every custom colour on the *Colors*
page (live in `a.fcol` / `a.col` / `a.rank_col`).

**Want your own settings?** Register your own MCM page in your own `<name>_mcm.script`, exactly
as any Anomaly mod does. Do not add options to Immersive Identification's pages.

---

## 10. Performance rules

`on_draw` runs **every frame, for every visible target**. The host mod is careful here and your
style should match it.

- **Allocate nothing per frame.** No `{}`, no `vector()`, no new strings. Put anything you need
  in `state` during `on_create`. This is the single biggest cost — per-frame garbage.
- **Use `ctx.show` and `ctx.set_text`**, not the raw `Show` / `SetText`. They skip the native
  call when nothing changed.
- **Cache anything expensive on `state`**, keyed by what it depends on. The pattern the built-in
  styles use for texture swaps:

  ```lua
  if state.icon_key ~= a.icon then
      state.icon:InitTexture(a.icon)
      state.icon_key = a.icon
  end
  ```

  Measuring text (`AdjustWidthToText` / `GetWidth`) is expensive — cache it against the string
  and only re-measure when the string actually changes.
- **Hoist repeated lookups.** `ctx.config._ui_kx` once at the top of `on_draw`, not four times.
- **Build strings with a table and `table.concat`**, never `..` in a loop.
- **Don't call engine queries you don't need.** You already have everything about the target in
  `a`; going back to `level.object_by_id` and re-querying is both slower and redundant.

---

## 11. Worked example: a bodycam-style outline

Uses `want_box` to get the target's projected head box and draws a four-strip rectangle around
it, with the name beside it. Shows box handling, text, nil-checking and caching together.

```lua
-- gamedata/scripts/myid_frame.script

local function on_create(state, ctx)
    state.top    = ctx.xml:InitStatic("tag_box_top", ctx.parent)
    state.bottom = ctx.xml:InitStatic("tag_box_bottom", ctx.parent)
    state.left   = ctx.xml:InitStatic("tag_box_left", ctx.parent)
    state.right  = ctx.xml:InitStatic("tag_box_right", ctx.parent)
    -- Created last, so the text draws on top of the frame.
    state.label  = ctx.xml:InitTextWnd("tag_name:text", ctx.parent)
    state.label_sh = ctx.xml:InitTextWnd("tag_name_sh:text", ctx.parent)
end

local function hide_all(state, ctx)
    ctx.show(state.top, false)
    ctx.show(state.bottom, false)
    ctx.show(state.left, false)
    ctx.show(state.right, false)
    ctx.show(state.label, false)
    ctx.show(state.label_sh, false)
end

local function on_draw(state, a, ctx)
    -- The box is nil whenever the target does not project this frame.
    if not (a.box_hw and a.box_hh) then
        hide_all(state, ctx)
        return
    end

    local kx = ctx.config._ui_kx
    local t  = 2                        -- edge thickness, virtual px
    local x0, y0 = a.box_cx - a.box_hw, a.box_cy - a.box_hh
    local w,  h  = a.box_hw * 2, a.box_hh * 2
    local tw = math.max(1, t * kx)      -- vertical edges: correct the WIDTH only
    local vh = math.max(1, h - 2 * t)   -- and butt them between top and bottom

    local col = a.sign and ctx.sign_colors[a.sign] or a.fcol
    local argb = GetARGB(a.a, col[1], col[2], col[3])

    state.top:SetWndSize(ctx.size(w, t))
    state.top:SetWndPos(ctx.position(x0, y0))
    state.top:SetTextureColor(argb)
    ctx.show(state.top, true)

    state.bottom:SetWndSize(ctx.size(w, t))
    state.bottom:SetWndPos(ctx.position(x0, y0 + h - t))
    state.bottom:SetTextureColor(argb)
    ctx.show(state.bottom, true)

    state.left:SetWndSize(ctx.size(tw, vh))
    state.left:SetWndPos(ctx.position(x0, y0 + t))
    state.left:SetTextureColor(argb)
    ctx.show(state.left, true)

    state.right:SetWndSize(ctx.size(tw, vh))
    state.right:SetWndPos(ctx.position(x0 + w - tw, y0 + t))
    state.right:SetTextureColor(argb)
    ctx.show(state.right, true)

    -- Name to the right of the box -- absent when the player turned it off.
    if a.name then
        ctx.set_text(state.label, a.name)
        ctx.set_text(state.label_sh, a.name)
        ctx.draw_shadowed_text(state.label, state.label_sh,
            a.box_cx + a.box_hw + 8, a.box_cy - a.box_hh,
            a.a, 236, 230, 218, math.floor(180 * a.a / 255))
    else
        ctx.show(state.label, false)
        ctx.show(state.label_sh, false)
    end
end

function on_game_start()
    if not ii_api then
        return
    end
    ii_api.register_style({
        id = "myid_frame",
        on_create = on_create,
        on_draw = on_draw,
        on_hide = hide_all,      -- on_hide(state, ctx, slot) -- same shape, reused directly
        want_box = true,
    })
end
```

Note the edges butt at the corners instead of overlapping (top and bottom span the full width,
the sides fill only the gap between them). Overlapping corners double-draw and darken at any
thickness above 1.

Note too that `want_box` styles should **not** set `dist_scale`: the box extents already come
from a world projection, so they shrink with distance on their own.

---

## 12. Debugging

- **Your style doesn't appear in the dropdown.** `on_game_start` didn't run, `ii_api` was nil, or
  registration was rejected — print the second return value of `register_style`.
- **The dropdown shows `my_bar` instead of a name.** Your string id is wrong. It must be exactly
  `ii_uistyle_general_ui_style_lst_<id>`, in a `<string_table>` XML under
  `gamedata/configs/text/eng/`.
- **It drew once and stopped.** Your hook threw. The log has one line:
  `!![ii_api] style 'x' errored, disabling it for this slot: ...`. The style stays off for that
  slot until you reload.
- **Widgets ignore your sizing / are huge.** `stretch="1"` (section 7).
- **Widgets linger on screen.** Your `on_hide` doesn't hide all of them.
- **Circles look like ovals.** You skipped `_ui_kx` on the width (section 8).
- **Nothing draws at all.** Check the target is actually being identified first: turn on *Debug
  draw* on the mod's Debug MCM page, which shows the aim point, the assist radius and every
  candidate in range. If the mod isn't acquiring the target, no style will draw.

Two settings make iterating much faster while developing: **Instant identify** (Debug/General)
removes the scan wait, and **Auto-identify visible targets** (Targeting) tags everything in view
without aiming.

---

## 13. Gotchas

A checklist of everything above that actually bites:

1. Register in `on_game_start`, never at a script's top level.
2. `ctx.position` / `ctx.size` return **shared scratch** — use inline, never store.
3. `stretch="1"` on every image widget you size from script.
4. Hide *every* widget you create in `on_hide`.
5. `a.sign` is `nil` when *Show relation* is off — guard it.
6. `a.box_*` is `nil` when the target doesn't project — guard it.
7. `a.name` / `a.header` / `a.rank` / `a.weap` are `nil` when the player turned them off.
8. Multiply widths by `_ui_kx`, not heights, and not on rotated widgets.
9. Multiply every dimension by `a.scale`, and every alpha by `a.a`.
10. Never store `a` itself, or any colour table from it — both are reused and live.
11. Allocate nothing in `on_draw`.
12. Prefix your `id` so it can't collide with another add-on.

### One caveat on saved settings

The player's UI style choice is stored as an **index**. The built-in styles hold the first eight
and never move. Add-on styles occupy the range above that, sorted by `id`, so a given set of
installed add-ons always produces the same indices no matter what order scripts load in — but
**installing or removing another style add-on can shift which one a saved setting points at.**
Players may need to re-pick their style after adding a new one. If an index points past the end
(the add-on was removed), the mod falls back to the Card style.

---

Questions, or something here is wrong or missing? Open an issue at
<https://github.com/dxshie/immersive_identification>.
