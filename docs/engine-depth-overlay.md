# Depth-aware bodycam overlay (box + text)

STATUS:
- **BOX — APPLIED (v2.30.0), needs rebuild + in-game test.** Engine globals
  `g_bodycam_overlay_rects[64*11]`/count + cvar `r__bodycam_overlay`; bindings
  `bodycam.overlay_begin/rect/commit`; `CBlender_bodycam_overlay` + shader
  `bodycam_overlay.ps` (flat colour via `overlay_color` const, alpha-blended);
  `CRenderTarget::phase_bodycam_overlay` (combine tail, main pass, `HW.pBaseZB`
  bound + `set_Z(TRUE)`, projects each rect's world anchor → NDC z, draws a TL quad
  at that z so the hardware depth test clips per-pixel). Lua: `draw_head_box`
  submits 4 world-anchored `overlay_rect`s (virtual coords; engine scales
  ×dwWidth/1024) + hides the CUIStatic edges; `render()` brackets `overlay_begin`/
  `overlay_commit` (committed on every exit incl. pip/suppress + teardown). Falls
  back to CUIStatic edges when the binding is absent.
- **TEXT — APPLIED (v2.31.0), needs rebuild + in-game test.** Font-to-RT: engine
  globals g_bodycam_text_buf[32][64]/data[32*9]/count; bindings bodycam.overlay_text
  _begin/add/commit; rt_bodycam_text ($user$bodycam_text, screen-sized A8R8G8B8);
  a lazy CGameFont m_bodycam_font ("hud_font_di", fsDeviceIndependent); shader
  bodycam_text.ps (sample s_text + same PS depth test as bodycam_overlay) + blender
  CBlender_bodycam_text (binds s_text + s_position). phase_bodycam_text: pass 1
  renders all lines into rt_bodycam_text with the font at their virtual coords;
  pass 2 composites each line onto the scene with a quad over its screen bbox
  (uv=virtual/1024,768), depth-tested by anchor view-depth. Called after phase_
  bodycam_overlay. Lua: draw_bodycam_line submits overlay_text (hides the CUIStatic
  name/faction/weapon) + overlay_text_begin/commit bracket. Falls back to CUIStatic.
  RISKS (untestable): font->OnRender() into an RT mid-combine (state/clear); text
  size/position vs the old CUIStatic. Tunables: font section + SetHeightI.
  v2.31.1 FIX: shader needs `Texture2D s_text;` declared (custom bound texture; only
  s_position comes from common.h). v2.31.2 FIX (no text visible): must use OutI
  (device-INDEPENDENT, coords 0..1 fractions) NOT Out (real px) -- with fractional
  coords = vx/1024,vy/768, the glyph lands at real px = fraction*dwWidth, which is
  ALSO the RT uv, so the composite samples where the glyph is. Also font "hud_font_di"
  -> "stat_font" (proven in svp_stats). Composite bbox is a fixed 380x19 virtual
  region (RT transparent outside glyphs). Needs rebuild.
- v2.30.1 FIX: switched from a HARDWARE depth test (relied on stub_screen_space VS
  preserving the vertex z -- it does NOT, so the box drew over everything) to a
  PIXEL-SHADER depth test like bodycam_redaction: sample s_position at SV_Position,
  discard where sceneZ < anchor_view_depth - 0.15. The blender now binds s_position
  (r2_RT_P); the pass computes the anchor's view depth (dot(anchor-camPos,camDir))
  and passes it as overlay_params.x; no depth buffer / set_Z needed. Kill switch:
  `r__bodycam_overlay 0`. Virtual→pixel scale (×dwWidth/1024) matches world2ui.


Goal: the bodycam UI (faction-coloured head rectangle + name/weapon text) must be
**per-pixel depth-aware** — clipped where the viewmodel or world geometry is in
front of the target (target behind a wall, or box edge over the gun). Today the box
and text are `CUIStatic` HUD widgets drawn in the 2D UI pass with **no depth
buffer**, so they always paint on top.

## Why an engine pass (not CUIStatic)

- The 2D UI/dialog pass runs on the backbuffer AFTER post-processing; the scene
  depth buffer (`HW.pBaseZB`) is no longer valid/bound there. So depth-testing UI
  in place is impossible.
- The scene depth (including the VIEWMODEL, drawn in the g-buffer/hud pass) is valid
  at the **combine tail** — exactly where `phase_redaction`/`phase_bodycam_corpse_redact`
  run. So the overlay draws there, onto the scene colour RT, with `set_Z(TRUE)` +
  `HW.pBaseZB` bound + depth func LESSEQUAL. The GPU depth test then clips each
  overlay pixel where the scene is nearer — walls AND the gun, per-pixel, for free.
- Side effect (desirable): the world-label now composites UNDER the HUD/crosshair
  (it's a world object), instead of over everything.

TL vertices carry a z (`FVF::TL::set(x,y,z,w,c,u,v)`, FVF.h:129); the depth buffer
stores NDC z. So each overlay element is drawn at its ANCHOR's projected NDC z.

## Depth from a world anchor

Lua submits each element's **world anchor position**; the engine projects it with
`Device.mFullTransform` (same as `world2ui_with_depth`, level_script.cpp:1908) and
keeps the real NDC z (`v_res.z = res._43/res._44`), remapped to [0,1] for the depth
buffer. All of an element's vertices use that single z. (The box is ~one depth; text
is a flat label at the head depth — one z per element is correct.)

## API (new bodycam.* bindings, mirrors the redaction begin/add/commit staging)

```
bodycam.overlay_begin()
bodycam.overlay_rect(x0,y0,x1,y1, r,g,b,a, wx,wy,wz)   -- screen px (real res), colour, world anchor
bodycam.overlay_text(x,y, str, r,g,b,a, align, wx,wy,wz)
bodycam.overlay_commit()
```
Staged into `g_bodycam_overlay_*` xrEngine globals (a rect list + a text list, each
entry carrying its world anchor). Screen coords are REAL pixels (Lua converts from
its 1024x768 virtual space: `px = vx / 1024 * Device.dwWidth`, etc.). Inert when the
binding is absent (older exe) — Lua keeps the CUIStatic path as a fallback (guarded).

## Engine: `CRenderTarget::phase_bodycam_overlay()` (combine tail, main pass)

Bind scene colour + depth, depth-test on:
```cpp
ref_rt& dst = o.dx10_msaa ? rt_Generic : rt_Color;
ID3DDepthStencilView* zb = o.dx10_msaa ? rt_MSAADepth->pZRT : HW.pBaseZB;
u_setrt(dst, nullptr, nullptr, zb);
RCache.set_Z(TRUE);           // hardware depth test vs the scene
// depth func LESSEQUAL is the default; overlay z <= scene z passes (not occluded)
RCache.set_Stencil(FALSE);
```
1. **Rects** — a simple colour blender (new `CBlender_bodycam_overlay`, alpha-blended,
   no texture; PS returns the vertex colour). Per rect: project its world anchor → z;
   emit two triangles (`FVF::TL`) at that z with the rect colour; draw. Batches fine.
2. **Text** — render each string into a shared offscreen RT with an UNMODIFIED
   `CGameFont`, then draw that RT as a depth-tested textured quad at the string's
   anchor z. Steps per string (or per target's text block):
   - `u_setrt(rt_bodycam_text, ...)`, clear to transparent.
   - A `CGameFont` (lazy, e.g. "hud_font_small") `Out(x,y,str)` + `OnRender()` into
     the RT (normal 2D — the font system is untouched, zero blast radius on other
     text). Lay the block at a known origin in the RT.
   - Back to `u_setrt(dst,...,zb)`, `set_Z(TRUE)`, draw a textured quad sampling the
     text RT, positioned at the on-screen text rect, all verts at the anchor z.
   - Reuse the RT per string block (serialised; fine for a handful of targets).
   (One RT big enough for the largest block, e.g. 512×192; or an atlas if batching.)
3. `CopyResource(rt_Generic_0, dst)` so later passes see it (same as phase_redaction),
   then `set_Z(FALSE)` restore.

Call from `phase_combine` tail, `!svp_pass_now`, main target, after the redaction
passes. Self-gates on overlay count 0.

## Lua changes (ii_identify.script)

- `draw_head_box` and the bodycam text block: when the overlay binding exists, submit
  `overlay_rect`/`overlay_text` with the head world anchor (already have `head_center`
  / `anchor_pos`) instead of positioning CUIStatic widgets; hide the CUIStatic ones.
  Keep the CUIStatic path as the fallback when the binding is absent.
- The box's 4 edges → 4 `overlay_rect` calls; name/weapon lines → `overlay_text`.
- All share the head/anchor world pos so they occlude together, per-pixel.

## Risk / verify
- Untestable here; needs `AnomalyDX11` rebuild. Watch: depth func direction (LESSEQUAL,
  overlay drawn where its z ≤ scene z), NDC-z→[0,1] remap matching the depth buffer,
  the font-to-RT state (clear alpha, font shader on an RT), and that drawing onto the
  scene colour at the combine tail composits correctly under the later HUD.
- Kill switch: cvar `r__bodycam_overlay 0` → engine skips the pass; Lua falls back to
  CUIStatic (or just hides — TBD) so there's an escape hatch.
- Font-to-RT keeps other game text untouched (no CGameFont/dxFontRender edits).
