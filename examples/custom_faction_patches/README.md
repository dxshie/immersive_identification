# Custom faction patches

A template for replacing the faction emblems on the tag with your own art.

By default Immersive Identification reuses the game's own faction icons — the `<community>_icon`
texture ids the vanilla character and relations screens use — so it needs no bundled art and
picks up whatever your modpack already has. Turning on **Custom faction patches** makes it ask
for **`ii_patch_<community>`** instead, which you supply.

## Doing it

**1. Draw the patches.** Square, alpha where you want transparency. 64×64 or 128×128 DXT5 is
plenty — the tag draws them small and a bigger source only costs VRAM. Save them as
`gamedata/textures/ui/ii_patch_<community>.dds`:

```
gamedata/textures/ui/ii_patch_stalker.dds
gamedata/textures/ui/ii_patch_dolg.dds
gamedata/textures/ui/ii_patch_freedom.dds
...
```

**2. Register the ids.** Copy
[`gamedata/configs/ui/textures_descr/ii_patch_textures.xml`](./gamedata/configs/ui/textures_descr/ii_patch_textures.xml)
from this folder and **delete the entries for factions you are not providing art for**. An id
registered against a file that does not exist is worse than no id at all. The community id is
the faction's internal name (`dolg`, not "Duty"); the file lists the ones this mod knows about.

**3. Enable it.** MCM → Immersive Identification → **UI Style → General → Custom faction
patches**.

It takes effect immediately, including on tags already on screen, so you can alt-tab, replace a
`.dds`, and check the result without re-identifying anything.

## Notes

- **It is all-or-nothing.** There is no way to ask the engine whether a texture id exists, so
  the mod cannot fall back per-faction. A faction you have not supplied a patch for shows no
  patch at all. Cover every faction you expect to meet, or accept the gaps.
- **Every style that draws an emblem uses these**: Card, Simple, Patch and the Crooks readout.
- **A single atlas works too.** Point several `<texture>` entries at one `<file>` and give each
  its own `x`/`y`/`width`/`height`, exactly as the mod's own `ii_textures.xml` does.
- **Unknown factions** — if your modpack adds a faction, add `ii_patch_<its community id>` and
  it is picked up with no script changes.

This folder is a template, not an installable mod: it deliberately ships no `.dds` files. If you
use G.A.M.M.A. and just want its patches rather than your own art, tick **GRIP Patches** in the
installer instead — it maps the same `ii_patch_*` ids onto G.A.M.M.A.'s existing atlas.
