if _userdata_DB == nil then _userdata_DB = {} end
if _userdata_DB.script_effects then return _userdata_DB.script_effects end

local udb = require('content_editor.database')
local core = require('content_editor.core')

--- @class ScriptEffectTypeDefinition
--- @field trigger_type string
--- @field category string
--- @field start fun(entity: ScriptEffectEntity, ctx: any): any data
--- @field stop nil|fun(entity: ScriptEffectEntity, data: any)
--- @field update nil|fun(entity: ScriptEffectEntity, data: any, deltaTime: number): shouldStop: boolean|nil

--- @class ScriptEffectEntity : DBEntity
--- @field trigger_type string
--- @field category string
--- @field data table

udb.register_entity_type('script_effect', {
    export = function (instance)
        --- @cast instance ScriptEffectEntity
        return { data = instance.data, trigger_type = instance.trigger_type, category = instance.category }
    end,
    import = function (data, entity)
        --- @cast entity ScriptEffectEntity
        entity = entity or {}
        entity.data = data.data or {}
        entity.category = data--[[@as any]].category
        entity.trigger_type = data--[[@as any]].trigger_type
        return entity
    end,
    insert_id_range = {1, 999990000},
    delete = function () return 'ok' end,
    root_types = {},
})

local main = require('content_editor.script_effects.effects_main')

_userdata_DB.script_effects = main

if core.editor_enabled then
    _userdata_DB.script_effects.ui = require('content_editor.script_effects.script_effects_ui')
end

return _userdata_DB.script_effects
