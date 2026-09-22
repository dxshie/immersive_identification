# Example add-ons

Complete, installable examples of extending Immersive Identification without editing it. The
first two register their own UI style through `ii_api`; the third needs no scripting at all.
None of them edits or overwrites any file of the host mod — this is the whole integration
surface.

Read [MODDERS.md](../MODDERS.md) for the guide; these are the same ideas as working code.

| | what it shows |
|---|---|
| **[ii_example_bar](./ii_example_bar)** | The minimum viable style. Registration, the three hooks, reusing the host mod's widget templates, the content toggles, distance scaling, aspect correction. **Start here.** |
| **[ii_example_frame](./ii_example_frame)** | `want_box` (the target's projected head/body extents, which drawing code cannot compute itself), shipping your own widget XML, text widgets with drop shadows, and caching. |
| **[custom_faction_patches](./custom_faction_patches)** | Not a style at all — a template for replacing the faction emblems with your own art, via the **Custom faction patches** MCM option. No Lua involved. |

## Trying one

Copy the example's `gamedata/` folder into a new mod folder in your mod manager, enable it
**below** Immersive Identification, and launch. Then:

For the two style examples: **MCM → Immersive Identification → UI Style → General → UI style**
— pick *Example Bar* or
*Example Frame*.

If it does not appear in the dropdown, see the debugging section of
[MODDERS.md](../MODDERS.md#12-debugging).

Two settings make iterating far faster: **Instant identify** removes the scan wait, and
**Auto-identify visible targets** (Targeting) tags everything in view without aiming.

## Using one as a starting point

Rename the files, the style `id`, and the string id to something of your own — the `id` is
global across every installed add-on, and the string id must match it exactly:

```
id = "my_thing"  ->  <string id="ii_uistyle_general_ui_style_lst_my_thing">
```

Prefix it with something specific to you so two add-ons can never collide.

These examples are checked by the repo's own tooling (`nix run .#check-xml`,
`.#check-lua`, `.#check-format`, `.#check-i18n`), so they stay valid as the mod evolves.
They are **not** included in the FOMOD release zip.
