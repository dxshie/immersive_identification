---@meta

-- ==========================================================================
-- game_object: the type returned by db.actor, level.get_target_obj(),
-- level.object_by_id(), etc. -- every NPC/monster/actor handle in the game.
-- src/xrGame/script_game_object*.cpp, class_<CScriptGameObject> registered
-- as "game_object" (script_game_object_script.cpp:24), spread across many
-- script_game_object_script*.cpp files via chained script_register_game_object*
-- helpers. See types/engine.lua for the file header/scope note.
--
-- CORE section: exactly what ii_identify.script/ii_mcm.script call.
-- EXTENDED section: additional bindings confirmed via direct C++ source
-- reads earlier in this project's development (each cited), not currently
-- called by this mod but kept here since game_object is the type most
-- likely to be extended next. All citations are file + line (or
-- approximate line, marked "~", when transcribed from an earlier summarized
-- research pass rather than a line this project's code re-verified directly).
-- ==========================================================================

---@class game_object
---@field enemy integer relation() enum value -- script_game_object_script2.cpp:38-45
---@field friend integer
---@field neutral integer
---@field dummy integer
game_object = {}

---------------------------------------------------------------------------
-- CORE (used by this mod)
---------------------------------------------------------------------------

---@return integer
function game_object:id() end

--- Exception-safe (SAFE_WRAP): false rather than an error on a dead/invalid
--- object. script_game_object_script2.cpp:121.
---@return boolean
function game_object:alive() end

--- Community/faction id string, e.g. "stalker", "bandit", "dolg". Only valid
--- for CInventoryOwner-derived objects (NPCs/actor).
--- script_game_object_inventory_owner.cpp:1039, bound script_game_object_script3.cpp:324.
---@return string
function game_object:character_community() end

---@param community string
---@param squad string?
---@param group string?
function game_object:set_character_community(community, squad, group) end

--- Profile/display name. script_game_object_inventory_owner.cpp:908, bound ~script3.cpp:314.
---@return string
function game_object:character_name() end

--- Rank id for CAI_Stalker objects ("novice"/"experienced"/"veteran"/
--- "master"/"expert"); SAFE_WRAP, logs and returns "" for non-stalkers
--- (monsters, the actor). Localise via "st_rank_" .. id (the same
--- convention this engine's own Discord Rich Presence integration uses,
--- src/xrGame/Actor.cpp:1442-1449).
--- script_game_object3.cpp:597-608, bound script_game_object_script2.cpp:147.
---@return string
function game_object:rank_name() end

--- Exception-safe. script_game_object_script2.cpp:133 -> GetRelationType.
---@param other game_object
---@return integer one of game_object.enemy/.friend/.neutral/.dummy
function game_object:relation(other) end

---@param bone string|integer bone name or index
---@param world boolean? default true
---@return Fvector
function game_object:bone_position(bone, world) end

---@return Fvector
function game_object:position() end

---@return Fvector
function game_object:direction() end

--- Currently held/wielded inventory item, or nil if holstered/empty.
--- script_game_object3.cpp:1018-1032, bound script_game_object_script2.cpp:156.
---@return game_object|nil
function game_object:active_item() end

--- Section (ltx config section) name, e.g. "wpn_binoc_inv".
--- script_game_object_script2.cpp:102.
---@return string
function game_object:section() end

--- Live camera-driven occlusion/visibility check (see the has_los() comment
--- in ii_identify.script for the full dispatch chain: for the actor this
--- goes through CActorMemory, a real per-triangle raycast against the
--- active player camera, refreshed ~every 100ms -- not an instantaneous
--- geometric ray). SAFE_WRAP.
--- script_game_object.cpp:311-335, bound script_game_object_script2.cpp:138.
---@param other game_object
---@return boolean
function game_object:see(other) end

---------------------------------------------------------------------------
-- EXTENDED (verified via C++ source in this project, not yet used here)
---------------------------------------------------------------------------

--- Class id. script_game_object_script2.cpp:99.
---@return integer
function game_object:clsid() end

--- Icon/portrait path. script_game_object_inventory_owner.cpp:~921, bound ~script3.cpp:315.
---@return string
function game_object:character_icon() end

--- Numeric rank value (raw threshold, varies per modpack -- prefer
--- rank_name() for display). ~script3.cpp:316.
---@return integer
function game_object:character_rank() end

---@param rank integer
function game_object:set_character_rank(rank) end

---@param delta integer
function game_object:change_character_rank(delta) end

--- ~script3.cpp:319-321.
---@return integer
function game_object:character_reputation() end

---@param value integer
function game_object:set_character_reputation(value) end

---@param delta integer
function game_object:change_character_reputation(delta) end

--- Per-object goodwill toward `other`. ~script_game_object_script3.cpp:299 -> GetGoodwill.
---@param other game_object
---@return integer
function game_object:goodwill(other) end

---@param value integer
---@param other game_object
function game_object:set_goodwill(value, other) end

---@param value integer
---@param other game_object
function game_object:force_set_goodwill(value, other) end

---@param delta integer
---@param other game_object
function game_object:change_goodwill(delta, other) end

--- Attitude enum toward `other`. ~script3.cpp:304 -> GetAttitude.
---@param other game_object
---@return integer
function game_object:general_goodwill(other) end

---@param relation_type integer ALIFE.ERelationType
---@param other game_object
function game_object:set_relation(relation_type, other) end

--- Goodwill toward an entire faction by community id string.
--- ~script3.cpp:307-308.
---@param community string
---@return integer
function game_object:community_goodwill(community) end

---@param community string
---@param value integer
function game_object:set_community_goodwill(community, value) end

---@return integer
function game_object:sympathy() end

---@param value integer
function game_object:set_sympathy(value) end

--- Numeric slot index of the currently active item.
--- script_game_object_inventory_owner.cpp:1671-1681, bound script_game_object_script2.cpp:358.
---@return integer
function game_object:active_slot() end

--- Item currently in a given inventory slot, or nil.
--- script_game_object_inventory_owner.cpp:1635-1647, bound script_game_object_script2.cpp:353.
---@param slot integer
---@return game_object|nil
function game_object:item_in_slot(slot) end

--- Currently active, non-hidden detector item (DETECTOR_SLOT), or nil.
--- script_game_object_inventory_owner.cpp:1557-1576, bound script_game_object_script2.cpp:354.
---@return game_object|nil
function game_object:active_detector() end

--- Single-slot (last-writer-wins!) per-object event registration -- see the
--- is_binoc_active() comment in ii_identify.script before using this on
--- db.actor for any callback type another mod might already claim. Calling
--- with just `callback_type` clears that slot.
--- script_game_object_script2.cpp:158-164.
---@param callback_type integer one of the `callback` enum
---@param fn fun(...: any)?
---@param obj any?
---@overload fun(self: game_object, callback_type: integer)
function game_object:set_callback(callback_type, fn, obj) end

--- ECallbackType enum for set_callback(). game_object_space.h; a subset
--- confirmed via src/xrGame/script_game_object_script.cpp and
--- src/xrGame/WeaponMagazined.cpp (zoom events).
---@class CallbackTypes
---@field weapon_zoom_in integer
---@field weapon_zoom_out integer
---@field key_press integer requires INPUT_CALLBACKS build define (on by default)
---@field key_release integer
---@field key_hold integer
---@field death integer
callback = {}
