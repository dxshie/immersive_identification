# Engine patch — dead-head glitch post-process (custom bodycam exe)

> **STATUS: APPLIED** to `/home/overlord/mnt/code/cpp/xray-monolith-bodycam`
> (branch `freeaim-identify-binding`), 7 files + `gamedata/shaders/r3/ii_glitch.ps`.
> Not yet compiled — rebuild the `AnomalyDX11` target in Visual Studio to produce
> the exe. Two deviations from the draft below, both deliberate:
> 1. **No scissor.** The pass draws a **fullscreen** quad and the region
>    restriction lives in `ii_glitch.ps` (it returns the scene untouched outside
>    `glitch_rect`). Reason: `phase_glitch` copies the whole target RT back into
>    the scene via `CopyResource`, so a scissored draw would leave everything
>    outside the box stale and corrupt the scene on copy-back — fullscreen +
>    in-shader masking is the correct, `phase_fakescope`-identical approach.
> 2. Modeled on `phase_fakescope` / `CBlender_fakescope` (the C++ blender path),
>    **not** the SVP lens `.s` system — `fakescope` has no `.s` file and neither
>    does `ii_glitch`; the blender's `r_Pass` handles VS/PS + states.

The mod (Lua + `gamedata/shaders/r3/ii_glitch.ps`) already ships the consumer
side and is inert until this binding exists.

The fork adds `draw_scope` / `s_svp_distort_stamp` / `svp_distort_stamp.ps` and
`bodycam_script.cpp`, which the stock `xray-monolith` lacks. This patch is modeled
on the stock **`phase_fakescope`** path (which `draw_scope` is a variant of); when
the mount is back, **first diff the fork's `draw_scope` + `svp_distort_stamp.ps`
+ `bodycam_script.cpp`** and prefer copying those exact idioms where they differ
from the citations below (paths are from stock `/home/overlord/code/cpp/xray-monolith`).

## Contract (already implemented on the Lua side)

```
bodycam.set_glitch_rect(x0, y0, x1, y1, intensity)   -- normalised [0,1] screen, top-left origin
bodycam.clear_glitch()
```

Renderer converts `[0,1] → pixels` (× `Device.dwWidth/dwHeight`) for the scissor
and passes the same `[0,1]` rect to the shader as `glitch_rect`.

## 1. Shared cross-module state (xrEngine)

`src/xrEngine/xr_ioc_cmd.cpp` (same channel as `ENGINE_API float ps_r2_sun_shafts_min`):

```cpp
ENGINE_API Fvector4 g_ii_glitch_rect      = {0.f, 0.f, 0.f, 0.f}; // normalised x0,y0,x1,y1
ENGINE_API float    g_ii_glitch_intensity = 0.f;
ENGINE_API bool     g_ii_glitch_active    = false;
```

(Declare the externs in a shared header, or `extern ENGINE_API ...;` at each use
site as the sun-shafts global does.)

## 2. Luabind export (xrGame)

In `src/xrGame/bodycam_script.cpp`, add to `Bodycam::script_register`'s
`module(L,"bodycam")[ ... ]` table:

```cpp
def("set_glitch_rect", &bc_set_glitch_rect),
def("clear_glitch",    &bc_clear_glitch)
```

Free functions in the same file:

```cpp
extern ENGINE_API Fvector4 g_ii_glitch_rect;
extern ENGINE_API float    g_ii_glitch_intensity;
extern ENGINE_API bool     g_ii_glitch_active;

static void bc_set_glitch_rect(float x0, float y0, float x1, float y1, float intensity) {
    g_ii_glitch_rect.set(x0, y0, x1, y1);
    g_ii_glitch_intensity = intensity;
    g_ii_glitch_active    = (intensity > 0.f) && (x1 > x0) && (y1 > y0);
}
static void bc_clear_glitch() { g_ii_glitch_active = false; }
```

`Bodycam::script_register(L)` is already invoked from
`src/xrServerEntities/script_engine_export.cpp` — no new call needed if the
`bodycam` module is already registered there (verify).

## 3. Blender (xrRenderPC_R4) — copy CBlender_fakescope

`blender_nightvision.{h,cpp}` (or a new `blender_ii_glitch.*` added to
`xrRender_R4.vcxproj`). Selects `ii_glitch.ps` and binds the scene RT to `s_image`:

```cpp
void CBlender_ii_glitch::Compile(CBlender_Compile& C) {
    IBlender::Compile(C);
    C.r_Pass("stub_screen_space", "ii_glitch", FALSE, FALSE, FALSE); // VS, PS=ii_glitch.ps, no fog/zt/zw
    C.r_dx10Texture("s_image", r2_RT_generic0);   // scene colour -> s_image
    C.r_dx10Sampler("smp_base");
    C.r_dx10Sampler("smp_nofilter");
    C.r_End();
}
```

Header: `class CBlender_ii_glitch : public IBlender { ... getComment()="ii_glitch"; }`.

## 4. Shader member + lifecycle (r4_rendertarget)

- `r4_rendertarget.h`: `IBlender* b_ii_glitch;`  and  `ref_shader s_ii_glitch;`  and
  `void phase_glitch();`
- `r4_rendertarget.cpp`: `b_ii_glitch = xr_new<CBlender_ii_glitch>();`  /
  `s_ii_glitch.create(b_ii_glitch, "r3\\ii_glitch");`  /  `xr_delete(b_ii_glitch);`

## 5. The pass — copy phase_fakescope + add scissor

Add `CRenderTarget::phase_glitch()` (e.g. in `rendertarget_phase_nightvision.cpp`
alongside `phase_fakescope`):

```cpp
void CRenderTarget::phase_glitch() {
    extern ENGINE_API Fvector4 g_ii_glitch_rect;
    extern ENGINE_API float    g_ii_glitch_intensity;

    u32 Offset = 0;
    u32 Cc = color_rgba(0,0,0,255);
    float d_Z = EPS_S, d_W = 1.f;
    float w = float(Device.dwWidth), h = float(Device.dwHeight);
    Fvector2 p0, p1; p0.set(0,0); p1.set(1,1);

    ref_rt& dest_rt = RImplementation.o.dx10_msaa ? rt_Generic : rt_Color;
    u_setrt(dest_rt, nullptr, nullptr, nullptr);
    RCache.set_CullMode(CULL_NONE);
    RCache.set_Stencil(FALSE);

    // Scissor to the head box (normalised -> pixels).
    Irect sc;
    sc.lt.set(int(g_ii_glitch_rect.x * w), int(g_ii_glitch_rect.y * h));
    sc.rb.set(int(g_ii_glitch_rect.z * w), int(g_ii_glitch_rect.w * h));
    RCache.set_Scissor(&sc);

    // Constants for ii_glitch.ps.
    RCache.set_c("glitch_params", g_ii_glitch_intensity, Device.fTimeGlobal, 10.f, 0.006f);
    RCache.set_c("glitch_rect",   g_ii_glitch_rect.x, g_ii_glitch_rect.y, g_ii_glitch_rect.z, g_ii_glitch_rect.w);

    FVF::TL* pv = (FVF::TL*)RCache.Vertex.Lock(4, g_combine->vb_stride, Offset);
    pv->set(0, h, d_Z, d_W, Cc, p0.x, p1.y); pv++;
    pv->set(0, 0, d_Z, d_W, Cc, p0.x, p0.y); pv++;
    pv->set(w, h, d_Z, d_W, Cc, p1.x, p1.y); pv++;
    pv->set(w, 0, d_Z, d_W, Cc, p1.x, p0.y); pv++;
    RCache.Vertex.Unlock(4, g_combine->vb_stride);

    RCache.set_Element(s_ii_glitch->E[0]);
    RCache.set_Geometry(g_combine);
    RCache.Render(D3DPT_TRIANGLELIST, Offset, 0, 4, 0, 2);

    RCache.set_Scissor(nullptr);
    HW.pContext->CopyResource(rt_Generic_0->pTexture->surface_get(), dest_rt->pTexture->surface_get());
}
```

Notes: `Irect` = `{lt,rb}` in pixels, casts to `RECT`; `set_Scissor` at
`dx10R_Backend_Runtime.h`. Confirm `Device.fTimeGlobal` field name in the fork
(else use `Device.dwTimeContinual/1000.f`). `s_ii_glitch->E[0]` = first pass;
match how the fork indexes `s_svp_distort_stamp->E[...]`.

## 6. Inject into the post chain

`src/Layers/xrRenderPC_R4/r4_rendertarget_phase_combine.cpp`, right **after** the
`if (scope_fake_enabled) phase_fakescope();` block (so: after tonemap/LUT, before
SMAA/TAA/combine and UI):

```cpp
extern ENGINE_API bool g_ii_glitch_active;
if (g_ii_glitch_active) phase_glitch();
```

## 7. Shader file

`gamedata/shaders/r3/ii_glitch.ps` — already written in this repo. It samples
`s_image` via `smp_base` (declared in the shared `common.h`), reads `glitch_params`
+ `glitch_rect`. No manifest; loaded by the `r_Pass(..., "ii_glitch", ...)` name.

## 8. Build

MSBuild (`src/engine-vs2022.sln`). New `.cpp` → the relevant `.vcxproj` +
`.filters` (`xrGame.vcxproj` for `bodycam_script.cpp` if new; `xrRender_R4.vcxproj`
if you split the blender/pass into new files — none needed if you extend existing
`blender_nightvision.*` / `rendertarget_phase_nightvision.cpp`). Game exe target:
`AnomalyDX11` in `xrEngine.vcxproj`.

## 9. Verify in-game

- `ui_style = Bodycam`, `Glitch dead targets` = on, identify an NPC, kill it →
  scene distorts inside the head box for `Glitch duration` s, box fades, then
  the tag clears.
- Stock exe (no binding): box still lingers `glitch_time` then clears, no
  distortion, no errors (the `rawget(_G,"bodycam")` guard).
- Confirm the scissor rect tracks the ragdoll head as it falls (bone_position
  keeps working on corpses).
