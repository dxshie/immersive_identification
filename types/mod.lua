---@meta

-- ==========================================================================
-- Cross-file globals specific to THIS mod (not general engine API -- see
-- engine.lua's header for that). In this engine's script loader, every
-- gamedata/scripts/X.script file's top-level non-local globals become
-- accessible from any OTHER loaded script as fields on a table literally
-- named `X` (confirmed by this project's own working code: ii_mcm.script
-- reads ii_identify.DEFAULTS/.MODIFIER_LIST/.DEFAULT_KEY_NAME, all declared
-- as bare globals in ii_identify.script). Stub that one table shape here so
-- ii_mcm.script's cross-file references resolve instead of showing as
-- undefined globals.
-- ==========================================================================

---@class ii_identify
---@field DEFAULTS table config defaults, keyed by MCM option id
---@field MODIFIER_LIST { dik: string?, alt_dik: string?, label: string }[]
---@field DEFAULT_KEY_NAME string DIK_keys field name, e.g. "DIK_X"
ii_identify = {}
