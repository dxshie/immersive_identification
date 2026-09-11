---@meta

-- ==========================================================================
-- Cross-file globals specific to THIS mod (not general engine API -- see
-- engine.lua's header for that). In this engine's script loader, every
-- gamedata/scripts/X.script file's top-level non-local globals become
-- accessible from any OTHER loaded script as fields on a table literally
-- named `X` (confirmed by this project's own working code: ii_mcm.script
-- reads ii_identify.DEFAULTS/.MODIFIER_LIST/.UI_STYLE_LIST/.DEFAULT_KEY_NAME,
-- all declared as bare globals in ii_identify.script). Stub that one table
-- shape here so ii_mcm.script's cross-file references resolve instead of
-- showing as undefined globals.
-- ==========================================================================

---@class ii_identify
---@field DEFAULTS table config defaults, keyed by MCM option id
---@field MODIFIER_LIST { dik: string?, alt_dik: string?, label: string }[]
---@field UI_STYLE_LIST { label: string }[]
---@field REDACT_STYLE_LIST { label: string }[]
---@field REDACT_AREA_LIST { label: string }[]
---@field BOX_COLOR_SOURCE_LIST { label: string }[]
---@field COLOR_DEFS { id: string, group: string, tbl: number[], def: number[] }[] configurable colours (MCM Colors section)
---@field get_last_identified fun(): table? last-identified target snapshot (name/faction/rank/weap/x/y/z/dist), or nil
---@field get_scan_progress fun(): number? progress 0..1 of the active scan (for the Promin OSD spinner), or nil
---@field get_wd_tier_cfg fun(): table resolved WD-compat tier config (for the compat driver)
---@field tier_provider (fun(): table?)? external tier-system provider (set by the WD compat addon)
---@field DEFAULT_KEY_NAME string DIK_keys field name, e.g. "DIK_X"
ii_identify = {}

-- Soft dependency: the separate Skill System mod (haru_skills.script, at
-- $HOME/code/lua/skillsystem, also shipped in a rebalanced form by the
-- "G.A.M.M.A. Skill System Balance" addon), stubbed only for the one entry
-- point ii_identify.script actually reads/writes (see its perception_level()
-- / award_perception_xp()) -- deliberately NOT haru_skills.increase_skill,
-- which both known variants of that file make unusable for any skill outside
-- their own hardcoded four (see award_perception_xp()'s comment). May
-- legitimately be nil at runtime -- this repo only ships the compatibility
-- skill_perception.ltx as an OPTIONAL FOMOD component (see
-- fomod/ModuleConfig.xml), so every real access is nil-chained rather than
-- assumed present.
---@class haru_skills
---@field skills_levels table<string, { current_level: number, max_level: number, experience: number, requirement: number }>
haru_skills = {}
