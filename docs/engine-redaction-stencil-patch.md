# Pending engine changes for redaction (apply on the next AnomalyDX11 rebuild)

Status:
- **Item 0 (shader rename) — DONE.**
- **Option B CORE (stencil silhouette, NO padding) — APPLIED (v2.28.0), needs
  rebuild + in-game verification.** Corpse redaction now draws where the g-buffer
  stencil bit 0x40 (tagged on corpse pixels) is set — exact silhouette, occlusion
  free. Files: IRenderable.h (`renderable_bodycam_redact`), GameObject.h (flag +
  `set_bodycam_redact`), script_game_object_use.cpp + _script3.cpp + .h (Lua binding),
  xr_ioc_cmd.cpp (`g_bodycam_redact_stencil` cvar + `g_bodycam_redact_corpse_mode/intensity`),
  r__dsgraph_render.cpp (the stencil tag, gated PHASE_NORMAL + TargetMain),
  bodycam_script.cpp (`bodycam.redact_corpse`), r4_rendertarget.{h,cpp} +
  phase_combine.cpp (`phase_bodycam_corpse_redact`), bodycam_redaction.ps (corpse path:
  `redaction_count.z` flag → fixed-px pixelate + no feather). Lua: corpse marks via
  `set_bodycam_redact` (update_redact_membership) + `bodycam.redact_corpse` per frame; no
  corpse rects. **In-scope (SVP) corpse redaction is dropped** (stencil is main-view
  only) — face in-scope still works. Kill switch: `r__bodycam_redact_stencil 0`.
- **PADDING — NOT YET (section 5 below).** Add after the core silhouette is
  confirmed in-game: resolve stencil → R8 mask RT → dilate in the shader.
- Per-box mode is effectively solved for corpse-vs-face (separate passes now).

Verify-on-build watch-items (untestable here): D3DCMP_/D3DSTENCILOP_ enum scope in
r__dsgraph_render.cpp; `RImplementation.phase`/`TargetMain` access; that the
per-item stencil override holds through `V->Render` (if a shader resets it, move the
`set_Stencil` to just before Render); `set_Z(FALSE)` for the corpse quad.

---

## 0. Rename the redaction shader → `bodycam_redaction` — ✅ DONE

Applied: `bodycam_redaction.ps` → `bodycam_redaction.ps` (mod + fork gamedata);
`blender_nightvision.cpp` `r_Pass "bodycam_redaction"`; `r4_rendertarget.cpp`
`create "r3\\bodycam_redaction"`; `getComment "bodycam_redaction"`. Internal C++
symbols (`g_bodycam_redaction_*`, `redaction_add`, `s_bodycam_redaction`, `phase_redaction`,
`CBlender_bodycam_redaction`) intentionally keep their names — only the shader FILE is
user-facing. Needs a rebuild to take effect (engine ref changes).

---

# Engine patch — Option B: per-object stencil silhouette mask for redaction

Goal: the dead-body redaction should hug the **exact corpse silhouette** at any
angle/distance, instead of a flat screen-space rect + depth-band approximation
(which under-covers a close/angled body and over-covers the surroundings).

Approach: tag the corpse's own pixels with a **stencil bit** during its normal
g-buffer draw, then the redaction pass stencil-tests that bit. Occlusion is free
(a corpse pixel only writes the bit if it passes the depth test during its draw),
and the skinned corpse mesh is reused (no re-render).

Target: `xray-monolith-bodycam` fork, `AnomalyDX11` (R4). All snippets are for the
DX11 path.

---

## Key facts established (from source)

- `phase_scene_begin()` (`r4_rendertarget_phase_scene.cpp:54`) sets the g-buffer
  stencil write:
  ```cpp
  RCache.set_Stencil(TRUE, D3DCMP_ALWAYS, 0x01, 0xff, 0x7f,
                     D3DSTENCILOP_KEEP, D3DSTENCILOP_REPLACE, D3DSTENCILOP_KEEP);
  ```
  ref `0x01`, read-mask `0xff`, **write-mask `0x7f`**, pass→REPLACE. So bits 0–6
  are writable; bit 7 (`0x80`) is reserved. **Bit 6 (`0x40`) is free.**
- Stencil bits already in use: `0x01` (scene/lighting present), `0x80` (masked
  with `0x81` in combine — reserved). `0x40` is unused → use it as REDACT_BIT.
- The dynamic scene draw loop is `CDSGraphManager::r_dsgraph_render_graph(...)`
  (`r__dsgraph_render.cpp:212`): per-packet, batched by sort key; each packet has
  `packet.item.pVisual / pObject / pMatrix`; `apply_object(item.pObject)` runs
  before `V->Render(...)`.
- Render items carry `pObject` as an `IRenderable*` (`xrEngine/IRenderable.h`).
  The render layer can't see game-object IDs, so mark via an IRenderable virtual.

REDACT_BIT = `0x40`. LIGHT_BIT = `0x01`. Corpse pixels get ref `0x41`.

---

## 1. IRenderable: a redact flag the render layer can read

`src/xrEngine/IRenderable.h` — add to the `IRenderable` interface:
```cpp
// Bodycam: when true, this object's g-buffer pixels are tagged
// with the redaction stencil bit so the redaction post-pass hugs its silhouette.
virtual bool renderable_bodycam_redact() const { return false; }
```
Default `false` means every other object is unaffected (no behavior change).

## 2. Game object: store + expose the flag

Find the `IRenderable` implementer for NPCs/creatures — `CGameObject`
(`src/xrGame/GameObject.h/.cpp`), which already implements `renderable_*`.

`GameObject.h`:
```cpp
private:
    bool m_bodycam_redact = false;
public:
    void set_bodycam_redact(bool b) { m_bodycam_redact = b; }
    virtual bool renderable_bodycam_redact() const override { return m_bodycam_redact; }
```
(If `CGameObject` isn't the direct `IRenderable`, put it on whatever class the
render item's `pObject` actually is — grep the class that overrides
`renderable_Render`. `renderable_bodycam_redact` must be reachable from `IRenderable*`.)

## 3. Lua binding: set the flag

`src/xrGame/script_game_object_script*.cpp` (where `game_object` methods are
registered), add:
```cpp
void CScriptGameObject::set_bodycam_redact(bool b)
{
    CGameObject* o = smart_cast<CGameObject*>(&object());
    if (o) o->set_bodycam_redact(b);
}
```
Register: `.def("set_bodycam_redact", &CScriptGameObject::set_bodycam_redact)`.
Declare in `script_game_object.h`.

## 4. G-buffer: tag corpse pixels (the one invasive spot)

`src/Layers/xrRender/r__dsgraph_render.cpp`, in `r_dsgraph_render_graph`'s
per-packet loop, inside the **`if (!static_geometry)`** block (dynamic objects only
— corpses are dynamic; ~line 313-318), right after `apply_object(item.pObject)` and
BEFORE `item.pVisual->Render(LOD)`:

```cpp
auto& item = packet.item;
bool ii_tag = false;   // declare before the !static_geometry block
if (!static_geometry)
{
    RCache.set_xform_world(*item.pMatrix);
    RImplementation.apply_object(item.pObject);
    RImplementation.apply_lmaterial();

    // Bodycam: tag this corpse's pixels with the redaction
    // stencil bit. Main opaque scene pass on the MAIN target only (not shadow /
    // not SVP); occluded pixels fail the depth test and aren't tagged (free
    // occlusion). set AFTER set_Element/apply so it isn't clobbered.
    extern int g_bodycam_redact_stencil; // r__bodycam_redact_stencil, default 1
    ii_tag = g_bodycam_redact_stencil
        && RImplementation.phase == CRender::PHASE_NORMAL
        && RImplementation.Target == RImplementation.TargetMain
        && item.pObject && item.pObject->renderable_bodycam_redact();
    if (ii_tag)
        RCache.set_Stencil(TRUE, D3DCMP_ALWAYS, 0x41, 0xff, 0x7f,
                           D3DSTENCILOP_KEEP, D3DSTENCILOP_REPLACE, D3DSTENCILOP_KEEP);
}

... calcLOD / set_LOD ...
item.pVisual->Render(LOD);

if (ii_tag)   // restore the plain scene stencil for the next item
    RCache.set_Stencil(TRUE, D3DCMP_ALWAYS, 0x01, 0xff, 0x7f,
                       D3DSTENCILOP_KEEP, D3DSTENCILOP_REPLACE, D3DSTENCILOP_KEEP);
```
The `!static_geometry` guard means only dynamic objects are ever considered, and
`renderable_bodycam_redact()` narrows to the mod's corpse set. Set the stencil AFTER
`apply_object` so a shader state change doesn't reset it before `Render`.

Global + cvar in `xr_ioc_cmd.cpp` (near the other `g_bodycam_*`):
```cpp
ENGINE_API int g_bodycam_redact_stencil = 1; // r__bodycam_redact_stencil: 0 disables the stencil tag
...
CMD4(CCC_Integer, "r__bodycam_redact_stencil", &g_bodycam_redact_stencil, 0, 1);
```

## 5. Resolve stencil → mask RT, then redact the DILATED (padded) mask

Padding needs the mask read back with a neighbourhood tap, so the stencil is first
resolved into a sampleable R8/RGBA mask, then the redaction shader dilates it by the
padding radius. Two sub-passes in `phase_redaction` (main pass only), before the
existing face-rect draw.

**5a. Mask RT** (`r4_rendertarget.{h,cpp}`): a screen-sized `rt_bodycam_redact_mask`
(`createUnique("$user$bodycam_redact_mask", w, h, D3DFMT_A8R8G8B8)`), member + create +
delete, mirroring `rt_Generic`. (Single-channel would be leaner but A8R8G8B8 is the
proven format here.)

**5b. Resolve pass** — draw white where the stencil bit is set:
```cpp
// bind the mask RT + the SCENE depth-stencil (for the stencil test)
u_setrt(rt_bodycam_redact_mask, nullptr, nullptr, HW.pBaseZB); // rt_MSAADepth->pZRT under msaa
FLOAT z[4] = {0,0,0,0}; HW.pContext->ClearRenderTargetView(rt_bodycam_redact_mask->pRT, z);
RCache.set_Stencil(TRUE, D3DCMP_EQUAL, 0x40, 0x40, 0x00);  // pass only where REDACT_BIT set
RCache.set_Element(s_bodycam_redact_mask->E[0]);                // PS outputs float4(1,1,1,1)
... fullscreen quad ...
RCache.set_Stencil(FALSE);
```
New trivial shader `gamedata/shaders/r3/bodycam_redact_mask.ps` (`return 1;`) + blender
`CBlender_bodycam_redact_mask` + `s_bodycam_redact_mask` (create "r3\\bodycam_redact_mask"). Runs
in the g-buffer stencil resolution, so occluded corpse pixels are already 0.

**5c. Redaction pass** — the existing `bodycam_redaction.ps` draw, now binding the
mask (`s_redact_mask` = rt_bodycam_redact_mask) and a pad constant:
```cpp
RCache.set_c("redact_mask_px", 1.f/w, 1.f/h, redact_mask_pad_px, 0.f); // texel size + pad radius (px)
```
`redact_mask_pad_px` from Lua's `redact_padding` mapped to px (e.g. a fixed base +
`redact_padding * K`, so 0 ⇒ ~2 px, 1 ⇒ ~24 px). Bind the mask texture in the
blender (`C.r_dx10Texture("s_redact_mask", ...)` — pass the rt name).

**Shader (`bodycam_redaction.ps`)**: a pixel is in the CORPSE silhouette if the
mask (DILATED by the pad radius) is set. Dilation = sample the mask at the centre +
a ring of taps at `pad` px (and optionally a half-radius ring); if any tap > 0.5,
covered. Then apply the effect (pixelate/black) — the mask IS the occlusion mask,
so **no depth band for corpses**. Keep the existing FACE-rect + depth-band path
(negative-depth boxes) unchanged, in the same shader: a pixel is redacted if
`(corpse mask dilated)` OR `(in a face rect and passes the face band)`.

Pixelate over the stencil mask: its cell grid can stay per-rect for face boxes; for
the maskless corpse silhouette use a GLOBAL screen-space cell grid (fine, the mask
clips it to the body). Sample `s_image` per usual.

Fallback: if `s_bodycam_redact_mask` / the stencil aren't available (older exe), the mask
is all-zero → corpses fall back to the existing rect + depth-band submission (Lua
keeps submitting corpse rects, see step 7). So `r__bodycam_redact_stencil 0` OR an old
exe both degrade to the current look.

## 6. In-scope (SVP) redaction

Unchanged — stays on the world-box + depth-band path (`phase_svp_redaction`). The
scope is a separate render (TargetSVP) with its own stencil; a stencil mask there
is a separate effort. So the SVP pass keeps `g_bodycam_redaction_world` + the band.

## 7. Lua: mark corpses, retire the main-pass band

`ii_identify.script`:
- In `update_corpse_membership`, after building `corpse_ids`, flag the objects:
  set `obj:set_bodycam_redact(true)` on current corpses and `false` on any that dropped
  out since last refresh (keep a `_redact_marked` table to diff). Guard the call
  (`if obj.set_bodycam_redact then ...`), so it's inert on a stock exe.
- The main-pass screen rects (`redaction_rects`) are still submitted for effect
  region/mode, but the depth/world data is now only needed for the SVP pass. No
  change strictly required to the feed — the stencil supersedes the main-pass
  depth band regardless of what depth is passed.
- On actor death / teardown, clear all `set_bodycam_redact(false)`.

Guard existence: `local HAS_REDACT_STENCIL = <first corpse>.set_bodycam_redact ~= nil`
or just `pcall`. Degrades to the current depth-band look on an exe without it.

---

## Risks / test plan

- **Blast radius**: the g-buffer stencil tag is the only shared-state change. If
  the per-item override leaks (not restored, or wrong pass), other objects get the
  redact bit → redaction bleeds onto them, OR lighting bit gets clobbered → dark/
  bright artifacts. Mitigate: gate strictly to PHASE_NORMAL + main viewport, always
  restore to `0x01`, and the `r__bodycam_redact_stencil 0` cvar kills it instantly.
- **Verify** with `r__bodycam_redact_stencil 1/0` toggling in-game: corpses redacted vs
  the depth-band fallback (shader still has it if you keep option-5-minimal).
- **MSAA**: depth-stencil is `rt_MSAADepth->pZRT` under msaa, `HW.pBaseZB` else —
  match `phase_scene_begin`.
- Corpses only: `renderable_bodycam_redact()` is only set on the mod's corpse set, so no
  other object is ever tagged.

Once applied + `AnomalyDX11` rebuilt, the redaction hugs the corpse silhouette,
respects occlusion for free, and needs no depth-band tuning on the main view.
