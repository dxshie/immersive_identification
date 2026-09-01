---@meta

-- ==========================================================================
-- Immersive Identification - engine type stubs (globals, level/game/db, UI)
-- ==========================================================================
-- EmmyLua annotations for the xray-monolith engine's Lua-exposed API, for
-- lua-language-server (and any other EmmyLua-compatible checker) to type-
-- check gamedata/scripts/*.script against. This is a `---@meta` file: it is
-- never actually loaded by the game, it exists purely so the language
-- server has something to resolve `device()`, `level.get_target_obj()`,
-- `game_object`, etc. against instead of flagging them as unknown globals.
--
-- Scope: every declaration here is either (a) exactly what
-- ii_identify.script/ii_mcm.script call, or (b) a directly-cited C++ binding
-- confirmed by reading this session's xray-monolith source (see the file:line
-- comments), extended a little beyond (a) where the same class/table is
-- already being stubbed and the extra members are cheap, useful, and
-- equally well-verified. Nothing here is guessed from memory of "how X
-- usually works" -- if it's not cited, it's because it was watched actually
-- run in this exact codebase, mirroring the standard this mod's own code
-- comments hold themselves to. Anything used by a future change to this mod
-- that ISN'T here yet should be added the same way: find the C++ binding
-- first, then stub it.
-- ==========================================================================

---------------------------------------------------------------------------
-- Standard Lua runtime
---------------------------------------------------------------------------
-- Not stubbed here: pcall, ipairs, pairs, math.*, string methods, etc. --
-- lua-language-server ships its own Lua 5.1 stdlib defs; .luarc.json in
-- this repo sets `runtime.version = "Lua 5.1"` (the version this engine
-- embeds) so those resolve without any of this file's help.

---------------------------------------------------------------------------
-- Fvector / Fvector2 / Frect
---------------------------------------------------------------------------
-- src/xrServerEntities/script_fvector_script.cpp: CScriptFvector::script_register,
-- global constructor `vector()`. Only the methods this mod actually calls
-- are stubbed (set/sub/distance_to/distance_to_sqr/normalize/magnitude);
-- the real class has many more (add/mul/div/lerp/mad/...).
---@class Fvector
---@field x number
---@field y number
---@field z number
local Fvector = {}

---@param x number|Fvector
---@param y number?
---@param z number?
---@return Fvector self
function Fvector:set(x, y, z) end

---@param a Fvector
---@param b Fvector?
---@return Fvector self
function Fvector:sub(a, b) end

---@param other Fvector
---@return number
function Fvector:distance_to(other) end

---@param other Fvector
---@return number
function Fvector:distance_to_sqr(other) end

---@return Fvector self
function Fvector:normalize() end

---@return number
function Fvector:magnitude() end

--- Constructs a new Fvector (uninitialised until :set()).
---@return Fvector
function vector() end

---@class Fvector2
---@field x number
---@field y number
local Fvector2 = {}

---@param x number
---@param y number
---@return Fvector2 self
function Fvector2:set(x, y) end

--- Constructs a new Fvector2.
---@return Fvector2
function vector2() end

---@class Frect
local FrectMethods = {}

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Frect self
function FrectMethods:set(x1, y1, x2, y2) end

--- Constructs a new Frect. Named identically to the type itself (the real
--- engine binding does this too) -- kept as a plain global function rather
--- than also being the class-shape local above, since lua-language-server
--- can't have one identifier be both a function and a table value.
---@return Frect
function Frect() end

--- Axis-aligned box, min/max in the SAME space the box was fetched in (e.g.
--- game_object:bounding_box() returns one in the object's local model
--- space -- see that method's own comment). No script-side constructor is
--- stubbed: the only source of one this mod uses is bounding_box().
--- src/xrServerEntities/script_fvector_script.cpp:162-165.
---@class Fbox
---@field min Fvector
---@field max Fvector
local FboxMethods = {}

--- The object's local-to-world transform matrix (game_object:xform()).
--- src/xrServerEntities/script_fmatrix_script.cpp:31,60-61.
---@class Fmatrix
local Fmatrix = {}

--- Transforms `p` by this matrix. Two overloads: write into a separate
--- output vector (leaving `p` untouched), or transform `p` in place.
---@param out_or_p Fvector destination (2-arg form) or the point to transform in place (1-arg form)
---@param p Fvector? the point to transform, when using the 2-arg form
function Fmatrix:transform(out_or_p, p) end

---------------------------------------------------------------------------
-- device() / RenderDevice
---------------------------------------------------------------------------
-- src/xrGame/script_render_device_script.cpp (CRenderDevice bound as
-- "render_device"); src/xrServerEntities/script_engine_script.cpp:91,
-- `def("device", &get_device)`.
---@class RenderDevice
---@field fov number field of view, degrees
---@field aspect_ratio number
---@field width number
---@field height number
---@field cam_pos Fvector active camera position
---@field cam_dir Fvector active camera direction (unit vector)
---@field cam_top Fvector active camera up vector
---@field cam_right Fvector active camera right vector
---@field time_delta number
---@field f_time_delta number
local RenderDevice = {}

---@return number # ms
function RenderDevice:time_global() end

---@return number
function RenderDevice:time_continual() end

---@return boolean
function RenderDevice:is_paused() end

---@param pause boolean
function RenderDevice:pause(pause) end

--- Returns the active render_device.
---@return RenderDevice
function device() end

---------------------------------------------------------------------------
-- Misc engine globals
---------------------------------------------------------------------------

--- Engine time in milliseconds (same clock as RenderDevice:time_global()).
---@return number # ms
function time_global() end

--- Packs an ARGB colour into the integer format the UI *Color setters take.
---@param a number 0-255
---@param r number 0-255
---@param g number 0-255
---@param b number 0-255
---@return number
function GetARGB(a, r, g, b) end

--- src/xrGame/key_binding_registrator_script.cpp:14-16, `pInput->iGetAsyncKeyState`.
--- Returns a raw C BOOL (marshalled as a Lua number, not a real boolean) --
--- compare with `~= 0`, don't trust plain truthiness.
---@param dik integer
---@return boolean|number
function key_state(dik) end

--- DIK/mouse scancode constants, e.g. DIK_keys.DIK_X, DIK_keys.DIK_LCONTROL.
--- Indexed dynamically (`DIK_keys[name]`) as often as accessed by dotted
--- field in real mod code, hence the index signature rather than an
--- exhaustive field list (the engine registers ~200 of these;
--- key_binding_registrator_script.cpp is the source of truth for the full set).
---@class DIKKeys
---@field DIK_X integer
---@field DIK_LCONTROL integer
---@field DIK_RCONTROL integer
---@field DIK_LSHIFT integer
---@field DIK_RSHIFT integer
---@field DIK_LMENU integer left Alt
---@field DIK_RMENU integer right Alt
---@field [string] integer
DIK_keys = {}

--- HUD holder; the object mod dialogs attach themselves to.
---@class Hud
local Hud = {}

---@param wnd CUIScriptWnd
function Hud:AddDialogToRender(wnd) end

--- Stock global (src/xrGame gamedata/scripts convention, not this engine's
--- C++): returns the current Hud, or nil before the HUD is built (e.g. at
--- on_game_start).
---@return Hud|nil
function get_hud() end

--- Pure-Lua broadcast registry (defined in the base game's _g.script, not
--- this repo's own C++): registers `fn` as one of possibly many listeners
--- for a named event (e.g. "actor_on_update"). Distinct from the engine's
--- own single-slot game_object:set_callback().
---@param event_name string
---@param fn function
function RegisterScriptCallback(event_name, fn) end

---------------------------------------------------------------------------
-- level
---------------------------------------------------------------------------
-- src/xrGame/level_script.cpp, CLevel::script_register, `module(L, "level")`.
---@class LevelApi
---@field ETraceTarget { Actor: integer, Camera: integer, Weapon: integer, Device: integer } level_script.cpp:2418-2424
level = {}

--- Object under the given trace source's crosshair (defaults to camera).
--- level_script.cpp:1947 `g_get_target_obj`, bound level_script.cpp:2446-2447.
---@param trace_target integer? one of level.ETraceTarget.*
---@return game_object|nil
function level.get_target_obj(trace_target) end

--- World point the given trace source is aimed at: `origin + dir * range` from
--- that source's SPickParam.barrel_matrix. For ETraceTarget.Weapon this is a
--- point along the actual rendered weapon barrel (includes free-aim / bodycam
--- offset), not the camera centre. Returns (0,0,0) when no such HUD item is
--- attached (e.g. no weapon in hand). level_script.cpp `g_get_target_pos`,
--- bound alongside get_target_obj. Confirmed on themrdemonized/xray-monolith
--- and asuparabekon/xray-monolith-bodycam (branch bodycam-mt).
---@param trace_target integer? one of level.ETraceTarget.*
---@return Fvector
function level.get_target_pos(trace_target) end

--- Distance to what the given trace source is aimed at. Bound alongside
--- get_target_obj / get_target_pos.
---@param trace_target integer? one of level.ETraceTarget.*
---@return number
function level.get_target_dist(trace_target) end

--- Iterates CGameObjects within `radius` of `pos`, nearest-to-farthest by
--- *world* distance to `pos` (not screen distance to anything). `fn`
--- returning true stops iteration early. level_script.cpp:2117-2137.
---@param pos Fvector
---@param radius number
---@param fn fun(obj: game_object): boolean|nil
function level.iterate_nearest(pos, radius, fn) end

---@param id integer
---@return game_object|nil
function level.object_by_id(id) end

--- Current in-game hour, 0..23. level_script.cpp:300 `get_time_hours`, bound
--- :2514. The same world clock the HUD watch and day/night cycle read.
---@return integer
function level.get_time_hours() end

--- Current in-game minute, 0..59. level_script.cpp:308 `get_time_minutes`,
--- bound :2515.
---@return integer
function level.get_time_minutes() end

--- Projects a world position into the engine's fixed 1024x768 virtual UI
--- space. `x < -9000` (or a nil return, depending on build) signals
--- off-screen/behind-camera. level_script.cpp:1769, bound :2800.
---@param pos Fvector
---@param hud boolean? default false
---@param allow_offscreen boolean? default false
---@return Fvector2|nil
function level.world2ui(pos, hud, allow_offscreen) end

---------------------------------------------------------------------------
-- ray_pick / rq_target (geometric raycast against the collision world)
---------------------------------------------------------------------------
-- src/xrGame/level_script.cpp: class_<CRayPick>("ray_pick") and the
-- enum_exporter<collide::rq_target> bound as the global "rq_target". Used here
-- by has_clear_ray() in ii_identify.script for a hard line-of-sight test that
-- db.actor:see() (a smoothed/cached memory read) can't provide.
--
-- Collision target flags -- what the ray is allowed to hit. Integer values are
-- the canonical X-Ray collide::rq_target enum (rqtStatic == 2).
---@class RqTarget
---@field rqtNone integer 0
---@field rqtObject integer 1  -- dynamic objects (NPCs, actor, physics)
---@field rqtStatic integer 2  -- static level geometry (walls/buildings)
---@field rqtShape integer 4
---@field rqtObstacle integer 8
---@field rqtBoth integer      -- rqtObject | rqtStatic
---@field rqtDyn integer
rq_target = {}

---@class RayPick
local RayPick = {}
---@param pos Fvector ray origin
function RayPick:set_position(pos) end
---@param dir Fvector normalized direction
function RayPick:set_direction(dir) end
---@param range number max distance along `dir` to test
function RayPick:set_range(range) end
---@param flags integer one of rq_target.* (collide::rq_target)
function RayPick:set_flags(flags) end
---@param obj game_object object excluded from the trace
function RayPick:set_ignore_object(obj) end
--- Runs the trace. Returns true if the ray HIT something within range
--- (i.e. the line is occluded) -- clear line of sight is `not query()`.
---@return boolean
function RayPick:query() end
---@return game_object|nil
function RayPick:get_object() end
---@return number
function RayPick:get_distance() end

--- Constructs a reusable ray. Also accepts (pos, dir, range, flags, ignore).
---@return RayPick
function ray_pick() end

---------------------------------------------------------------------------
-- utils_obj (stock Lua-side globals, gamedata/scripts/utils_obj.script --
-- clsid-based object-class checks, not this repo's C++)
---------------------------------------------------------------------------
---@param obj game_object
---@return boolean
function IsStalker(obj) end

---@param obj game_object
---@return boolean
function IsMonster(obj) end

--- Stock Lua-side global (gamedata/scripts/_g.script): C-printf-style logging
--- to the engine log (xray_*.log), flushed. Extra args fill %s/%d/... in `fmt`.
---@param fmt string
---@param ... any
function printf(fmt, ...) end

---------------------------------------------------------------------------
-- game (stock Lua-side global table, not this repo's C++ -- confirmed
-- present/used exactly as `level.world2ui`'s sibling in the reference mod
-- this project was modelled on)
---------------------------------------------------------------------------
---@class GameApi
game = {}

---@param id string
---@return string
function game.translate_string(id) end

---@param pos Fvector
---@param hud boolean?
---@param allow_offscreen boolean?
---@return Fvector2|nil
function game.world2ui(pos, hud, allow_offscreen) end

---------------------------------------------------------------------------
-- db (stock global; db.actor is the player's game_object)
---------------------------------------------------------------------------
---@class DbApi
---@field actor game_object|nil
db = {}

---------------------------------------------------------------------------
-- ini_sys -- the global system.ltx CScriptIniFile (stock global; every
-- item/weapon/etc. section and its fields live here). Only the one reader
-- this mod calls is stubbed. src/xrServerEntities/script_ini_file_script.cpp.
---------------------------------------------------------------------------
---@class CScriptIniFile
ini_sys = {}

--- Reads a string field from a section. Throws (SAFE-guard at call sites)
--- if the section/field is missing. script_ini_file_script.cpp:196.
---@param section string
---@param field string
---@return string
function ini_sys:r_string(section, field) end

--- True if the given section exists. script_ini_file_script.cpp:189.
---@param section string
---@return boolean
function ini_sys:section_exist(section) end

---------------------------------------------------------------------------
-- MCM (Mod Configuration Menu) -- optional, only present if MCM is
-- installed; code must guard with `ui_mcm and ui_mcm.get` before use.
---------------------------------------------------------------------------
---@class UiMcmApi
ui_mcm = {}

---@param path string e.g. "ii/main/enabled"
---@return any
function ui_mcm.get(path) end

---------------------------------------------------------------------------
-- utils_data -- a base Anomaly/GAMMA bundled script (gamedata/scripts/
-- utils_data.script, not part of this mod), always present in any real
-- install; stubbed only for the one function this mod actually calls.
---------------------------------------------------------------------------
---@class UtilsDataApi
utils_data = {}

--- Replaces "$key" tokens in str with the corresponding value from repl
--- (stringified). Used throughout the Skill System mod's own UI code for
--- the exact same purpose (e.g. ui_haru_skills.script's
--- `local parse_keys = utils_data.parse_string_keys`).
---@param str string
---@param repl table<string, any>
---@return string
function utils_data.parse_string_keys(str, repl) end

---------------------------------------------------------------------------
-- OOP helpers (a class-lib style shim bundled with the base game, not
-- standard Lua): `class "Name" (Base)` declares a class; `super()` inside
-- `:__init()` calls the base constructor. lua-language-server can't fully
-- infer types through this dynamic pattern -- annotate concrete classes
-- with `---@class Name : Base` directly above the `class "Name" (Base)`
-- line in the mod script itself for real completion/checking on `self`.
---------------------------------------------------------------------------

---@param name string
---@return fun(base: table): table
function class(name) end

function super(...) end

---------------------------------------------------------------------------
-- UI base classes
---------------------------------------------------------------------------
-- src/xrGame/ui/UIWindow_script.cpp and friends (CUIWindow/CUIFrameWindow/
-- CUIScriptWnd family); src/xrGame/ui_export_script.cpp. A genuine global
-- (not local): mod code passes it by name as a base class, e.g.
-- `class "IiTags" (CUIScriptWnd)`.
---@class CUIScriptWnd
CUIScriptWnd = {}

---@param rect Frect
function CUIScriptWnd:SetWndRect(rect) end

---@param auto_delete boolean
function CUIScriptWnd:SetAutoDelete(auto_delete) end

--- Parses a UI xml template file (relative to gamedata/configs/ui).
---@class CScriptXmlInit
local CScriptXmlInitMethods = {}

---@param file_name string
function CScriptXmlInitMethods:ParseFile(file_name) end

--- Instantiates a static/texture element from a named xml node.
---@param node_path string
---@param parent CUIScriptWnd
---@return CUIStatic
function CScriptXmlInitMethods:InitStatic(node_path, parent) end

--- Instantiates a text element from a named xml node (path convention
--- "node:text" picks the <text> child of that node).
---@param node_path string
---@param parent CUIScriptWnd
---@return CUIStatic
function CScriptXmlInitMethods:InitTextWnd(node_path, parent) end

--- Constructs a new CScriptXmlInit. Named identically to the type itself
--- (the real engine binding does this too) -- see the Frect() comment above
--- for why this can't also be the class-shape local.
---@return CScriptXmlInit
function CScriptXmlInit() end

--- A CUIStatic-family widget instance (as returned by InitStatic/InitTextWnd).
--- Only the members this mod calls are stubbed; the real class exposes a
--- great deal more (colour animation, 3-slice textures, etc.).
---@class CUIStatic : CUIScriptWnd
local CUIStatic = {}

---@param visible boolean
function CUIStatic:Show(visible) end

---@param pos Fvector2
function CUIStatic:SetWndPos(pos) end

---@param size Fvector2
function CUIStatic:SetWndSize(size) end

---@param argb number see GetARGB()
function CUIStatic:SetTextureColor(argb) end

--- Rotation in radians; must call EnableHeading(true) once first.
---@param radians number
function CUIStatic:SetHeading(radians) end

---@param enable boolean
function CUIStatic:EnableHeading(enable) end

--- Swaps the element's texture to a different registered texture id.
---@param texture_id string
function CUIStatic:InitTexture(texture_id) end

---@param text string
function CUIStatic:SetText(text) end

---@param argb number
function CUIStatic:SetTextColor(argb) end

--- Resizes the widget's bounding box to fit its current text content.
function CUIStatic:AdjustWidthToText() end

---@return number
function CUIStatic:GetWidth() end

--- Opaque font handle (CGameFont*). No fields/methods stubbed -- this mod
--- only ever passes one straight from GetFont() into SetFont() on another
--- widget, never inspects it. src/xrGame/ui/UILines.h:22-23,
--- src/xrGame/ui/UIStatic_script.cpp:54-55 (CUITextWnd::SetFont/GetFont;
--- the InitTextWnd-returned widgets in this stub's unified CUIStatic).
---@class CGameFont
local CGameFont = {}

---@param font CGameFont
function CUIStatic:SetFont(font) end

---@return CGameFont
function CUIStatic:GetFont() end

---------------------------------------------------------------------------
-- PiP (picture-in-picture scope), fork-specific -- optional, soft dependency
---------------------------------------------------------------------------
-- Only registered on an xray-monolith-pip engine build (or a fork built on
-- it, e.g. the "bodycam" fork) -- absent on stock xray-monolith and vanilla
-- Anomaly, same soft-dependency situation as haru_skills in mod.lua. Every
-- real call in ii_identify.script is gated behind PIP_AVAILABLE (a rawget(_G,
-- ...) existence check) precisely because these can be nil at runtime.
-- src/xrGame/console_registrator_script.cpp (xray-monolith-pip).

--- True while a real PiP scope is actively rendering via the second
--- viewport (reflex/iron/non-PiP sights never set it).
---@return boolean
function is_svp_active() end

--- Clears the current frame's pending UI-marker list, staged on the script/
--- logic thread. Call once per frame before any svp_ui_markers_add() calls.
function svp_ui_markers_begin() end

--- Stages one marker for this frame's PiP overlay, up to
--- CSecondVPParams::svp_ui_marker_max (8). Drawn as a filled disc (r/g/b/a)
--- with a ring around it (ring_r/g/b, same alpha as the fill) -- two colour
--- signals in one shape, since the shader has no text/icon capability to
--- show them separately. All colour components are 0..1, not 0..255.
--- Silently dropped past the cap.
---@param wx number
---@param wy number
---@param wz number
---@param r number
---@param g number
---@param b number
---@param a number
---@param radius number
---@param ring_r number
---@param ring_g number
---@param ring_b number
---@param scanning boolean true draws a rotating spinner arc instead of fill+ring (fill's a is still used as the spinner's own alpha)
function svp_ui_markers_add(wx, wy, wz, r, g, b, a, radius, ring_r, ring_g, ring_b, scanning) end

--- Publishes the markers staged since the last svp_ui_markers_begin() as one
--- atomic snapshot for the render thread to project through its own,
--- same-frame SVP camera -- call once per frame after the last add(), even
--- if zero markers were staged (an empty publish is what clears a stale
--- marker list once the last target stops qualifying).
function svp_ui_markers_commit() end
