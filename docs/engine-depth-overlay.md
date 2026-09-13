# Depth-aware bodycam overlay (box + text)

STATUS:
- **TEXT — REWRITTEN as a direct glyph emitter (current), needs rebuild + in-game
  test.** Root cause of the v2.31..v2.38 empty-RT failures, confirmed by reading the
  engine: `CGameFont::Out()` only *queues* strings; the real draw is
  `dxFontRender::OnRender` (`dxFontRender.cpp:25`), which sets ONLY its shader and
  inherits the live render STATE + TRANSFORM. Mid-combine that transform is the 3D
  camera, so the font's screen-space verts were mangled → empty `rt_bodycam_text`.
  Clean-state (v2.36) and captured-2D-transform replay (v2.38) both chased the symptom.
  **Fix:** delete `CGameFont` from the render loop. `phase_bodycam_text` Pass 1 now
  rasterises glyphs itself — for each submitted line it builds screen-space `FVF::TL`
  glyph quads (UVs = `TCMap/atlasPx`) into `rt_bodycam_text` via a new shader
  `bodycam_glyph.ps` + `CBlender_bodycam_glyph` (binds the font atlas as `s_base` from
  the `.create()` texture) — the SAME proven path the overlay rects use, so the
  transform is irrelevant. The font (`stat_font`) is kept only as an atlas/metrics
  provider (`CharTC`/`HeightNative`/`Interval`/`AtlasTexture` added to `GameFont`); atlas
  pixel dims read from the bound atlas at pass time. Pass 2 (`bodycam_text.ps` composite,
  depth-tested vs `s_position`) is UNCHANGED — it always worked. Lua: `DEPTH_TEXT=true`,
  `draw_bodycam_line` → `overlay_text_add`. Files: `bodycam_glyph.ps` (new),
  `blender_nightvision.{h,cpp}`, `r4_rendertarget.{h,cpp}`, `r4_rendertarget_phase_combine.cpp`
  (Pass 1), `GameFont.{h,cpp}`. Assumes ASCII/single-byte text (stat_font). `TEXT_VH`
  (15 virtual px) tunes line height. The old `g_bodycam_ui_xform_*` capture in
  `r4_R_render.cpp` is now inert (unused) — safe to remove on a later pass. Debug:
  `r__bodycam_text_debug 3` shows the raw glyph RT, `2` = magenta geometry test.
- (superseded) below: the original box + font-to-RT text notes.
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
  DIAGNOSIS (debug 3 = black RT even after v2.36.0 clean-state): dxFontRender::OnRender
  sets ONLY the shader -- it inherits the current STATE **and TRANSFORM**. Mid-combine
  the xform is the 3D camera, which mangles the font's screen-space verts -> empty RT.
  Clean state alone (v2.36.0) didn't fix it -> it's the transform.
  v2.38 FIX (engine, needs rebuild): CAPTURE the 2D UI transform (get_xform_world/
  view/project) at frame-end in r4_R_render.cpp (right before svp_stats::draw_overlay,
  where the font provably renders) into g_bodycam_ui_xform_{w,v,p}; RESTORE it in
  phase_bodycam_text before F.OnRender() (save/restore around it). Capture-and-replay
  avoids guessing the ortho matrix. Debug: r__bodycam_text_debug 1 logs the captured P
  matrix diag (ortho vs perspective). Verify with debug 3 (raw RT) after rebuild.
- v2.30.1 FIX: switched from a HARDWARE depth test (relied on stub_screen_space VS
  preserving the vertex z -- it does NOT, so the box drew over everything) to a
  PIXEL-SHADER depth test like bodycam_redaction: sample s_position at SV_Position,
  discard where sceneZ < anchor_view_depth - 0.15. The blender now binds s_position
  (r2_RT_P); the pass computes the anchor's view depth (dot(anchor-camPos,camDir))
  and passes it as overlay_params.x; no depth buffer / set_Z needed. Kill switch:
  `r__bodycam_overlay 0`. Virtual→pixel scale (×dwWidth/1024) matches world2ui.
- v2.34.0 (box clipped by ground): tried ANCHOR mode -- pass re-projects the head
  world anchor to a screen pixel (overlay_params.yzw) and the shader samples
  s_position THERE (not SV_Position) so the whole box shows/hides on head visibility.
  REVERTED in v2.37.1: the engine's re-projection (mFullTransform at combine-tail)
  didn't reliably match where Lua drew the box (Lua's world2ui runs at game-update
  with the prev-frame transform + possible convention mismatch), so the anchor pixel
  landed off the head -> sceneZ never indicated occlusion -> the WHOLE box stopped
  being depth-aware. Shader reverted to per-pixel (bias 0.15), runtime-loaded, NO
  rebuild. Ground clipping returns (acceptable -- depth-awareness > ground cosmetic).
  PROPER anchor fix (deferred, needs rebuild): don't re-project in the engine -- have
  Lua pass its OWN computed screen anchor (box_cx,box_cy from world2ui) through the
  overlay_rect binding (add ax,ay params); engine samples s_position at (ax*kx,ay*ky).
  Guarantees the sample matches the drawn box. Then all 4 edges test the head pixel
  -> whole box occludes on head visibility, no ground clip.
- v2.38.0 (final box behaviour, shader-only, no rebuild): DROPPED world depth-awareness
  entirely. The box now DRAWS over walls/ground (target behind a wall still shows its
  box) but is masked off the VIEWMODEL: s_position at the box pixel < VIEWMODEL_MAX
  (2.0 m, tunable #define) = the gun/hands (rendered near) -> discard; world geometry
  at the target is far, so it's kept. HUD/crosshair draw in a later 2D pass -> already
  on top. overlay_params still set by the engine but unused. This is the user's chosen
  final behaviour (no ground clip, no wall occlusion, just never over the gun/HUD).


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
