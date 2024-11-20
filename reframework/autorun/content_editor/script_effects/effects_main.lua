if _userdata_DB == nil then _userdata_DB = {} end
if _userdata_DB.script_effects then return _userdata_DB.script_effects end

local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local enums = require('content_editor.enums')
local info = require('content_editor.gameinfo')

--- @type table<string, ScriptEffectTypeDefinition>
local definitions = {}
local types = {}

local types_enum = enums.get_virtual_enum('_content_editor_custom_effects', {})

local categories = {'world'}
local alwaysCategories = {['world'] = function () end}

--- @type table<integer, table<EffectContext, EffectData[]>> {[effect_id] = {[context] = {data1, data2, ...}}}
local active_effects = {}

--- @param definition ScriptEffectTypeDefinition
local function register_effect_type(definition)
    if not definition[definition.effect_type] then
        types[#types+1] = definition.effect_type
    end
---@diagnostic disable-next-line: assign-type-mismatch
    types_enum.labelToValue[definition.label or definition.effect_type] = definition.effect_type
    definitions[definition.effect_type] = definition
end

--- @param effect_type string
--- @return ScriptEffectTypeDefinition|nil
local function find_definition(effect_type)
    return definitions[effect_type]
end

local function get_effect_types()
    return types_enum
end

udb.events.on('ready', function ()
    types_enum.resort()
end)

local _has_update_callback = false
local function start_update_callback()
    if _has_update_callback then return end
    _has_update_callback = true
    local last_update_time = os.clock()
    re.on_application_entry('UpdateBehavior', function ()
        local time_now = os.clock()
        local delta = time_now - last_update_time
        last_update_time = time_now
        if not info.is_ingame_unpaused() then return end
        local stoppedEffects = {}
        for effectId, effectContexts in pairs(active_effects) do
            local effect = udb.get_entity('script_effect', effectId) --[[@as ScriptEffectEntity|nil]]
            -- "continue" please do you know it lua, please, let me continue
            if effect then
                local def = definitions[effect.effect_type]
                if def.update then
                    for _, dataList in pairs(effectContexts) do
                        for _, data in ipairs(dataList) do
                            local success, shouldStop = pcall(def.update, effect, data, delta)
                            if not success or shouldStop == true then
                                stoppedEffects[#stoppedEffects+1] = {effect.id, data.context}
                                if not success then
                                    print('ERROR in script effect update ', effect.id, shouldStop)
                                    log.error('Script effect update error ['..effect.id..']: '..tostring(shouldStop))
                                end
                            end
                        end
                    end
                end
            end
        end

        for _, indexAndCtx in ipairs(stoppedEffects) do
            _userdata_DB.script_effects.stop(indexAndCtx[1], indexAndCtx[2])
        end
    end)
end

--- @return string[]
local function get_effect_categories(allowedExtraCategories)
    local list = {}
    for type, def in pairs(definitions) do
        if alwaysCategories[def.category] or utils.table_contains(allowedExtraCategories, def.category) then
            list[#list+1] = type
        end
    end
    list = utils.get_sorted_table_values(list)
    return list
end

--- @param name string
--- @param alwaysContextProvider nil|fun(): any Function for fetching the data if the effect can always be triggered (e.g. the player entity or similar)
local function add_effect_category(name, alwaysContextProvider)
    categories[#categories+1] = name
    if alwaysContextProvider then
        alwaysCategories[name] = alwaysContextProvider
    end
end

--- @param effectId integer
--- @param data EffectData
local function start(effectId, data)
    if effectId == 0 then return end
    local effect = udb.get_entity('script_effect', effectId) --[[@as ScriptEffectEntity]]
    if not effect then
        print('ERROR: script effect ', effectId, 'not found')
        return
    end

    local trigger = definitions[effect.effect_type]
    if trigger then
        local newData = trigger.start(effect, data)
        if newData == nil then
            newData = data
        elseif newData ~= data or newData.context ~= data.context then
            newData.context = data.context
        end

        active_effects[effectId] = active_effects[effectId] or {}
        local effect_data = active_effects[effectId]

        effect_data[data.context] = effect_data[data.context] or {}
        effect_data[data.context][#effect_data[data.context]+1] = newData
        if trigger.update then
            start_update_callback()
        end
    end
end

--- @param id integer
--- @param context EffectContext The context object that was used to start the script effect initially
local function stop(id, context)
    local effect = udb.get_entity('script_effect', id) --[[@as ScriptEffectEntity]]
    if not effect then return end

    local effect_data = active_effects[id]
    local effect_context = effect_data and effect_data[context]
    if effect_context and #effect_context > 0 then
        local trigger = definitions[effect.effect_type]
        local idx = #effect_context
        if trigger.stop then
            trigger.stop(effect, effect_context[idx])
        end
        if idx == 1 then
            active_effects[id][context] = nil
            if not next(active_effects[id]) then
                active_effects[id] = nil
            end
        else
            table.remove(effect_context, idx)
        end
    else
        print('WARNING: attempted to stop inactive script event', effect.effect_type, id, effect_context)
    end
end

local function stop_all_effects()
    for effectId, effectContexts in pairs(active_effects) do
        local effect = udb.get_entity('script_effect', effectId) --[[@as ScriptEffectEntity|nil]]
        -- "continue" please do you know it lua, please, let me continue
        if effect then
            local def = definitions[effect.effect_type]
            if def.stop then
                for context, dataList in pairs(effectContexts) do
                    for _, data in ipairs(dataList) do
                        pcall(def.stop, effect, data)
                    end
                end
            end
        end
    end

    active_effects = {}
end

helpers.hook_game_load_or_reset(stop_all_effects)
re.on_script_reset(stop_all_effects)

register_effect_type({
    effect_type = 'group',
    category = 'world',
    label = 'Effect group',
    start = function (entity, data)
        for _, subId in ipairs(entity.data.ids or {}) do
            start(subId, data)
            data.ids[#data.ids+1] = subId
        end
    end,
    stop = function (entity, data)
        for _, subId in ipairs(data.ids or {}) do
            stop(subId, data.context)
        end
    end
})

register_effect_type({
    effect_type = 'random',
    category = 'world',
    label = 'Randomly selected effect',
    start = function (entity, data)
        local ids = entity.data.ids or {}
        local idCount = #ids
        if idCount == 0 then return {id = -1} end
        data.id = ids[math.random(1, #ids)]
        start(data.id, data)
    end,
    stop = function (entity, data)
        if data.id and data.id ~= -1 then
            stop(data.id, data.context)
        end
    end
})

register_effect_type({
    effect_type = 'script',
    category = 'world',
    label = 'Custom script',
    start = function (entity)
        local script = entity.data.start_script_id and udb.get_entity('custom_script', entity.data.start_script_id)
        if script then
            local success, data = _userdata_DB.custom_scripts.try_execute(script, entity)
            if success then
                return data
            else
                print('ERROR: start script failed', data)
            end
        end
    end,
    update = function (entity, data, deltaTime)
        local script = entity.data.update_script_id and udb.get_entity('custom_script', entity.data.update_script_id)
        if script then
            local success, shouldStop = _userdata_DB.custom_scripts.try_execute(script, entity, data, deltaTime)
            if not success or shouldStop then
                if not success then
                    print('ERROR: update script failed', shouldStop)
                end
                return true
            end
        end
    end,
    stop = function (entity, data)
        local script = entity.data.stop_script_id and udb.get_entity('custom_script', entity.data.stop_script_id)
        if script then
            local success, error = _userdata_DB.custom_scripts.try_execute(script, entity, data)
            if not success then
                print('ERROR: stop script failed', error)
            end
        end
    end
})

_userdata_DB.script_effects = {
    _find_definition = find_definition,

    add_effect_category = add_effect_category,
    register_effect_type = register_effect_type,
    get_effect_categories = get_effect_categories,
    get_effect_types = get_effect_types,

    start = start,
    stop = stop,
    stop_all_effects = stop_all_effects,
}

return _userdata_DB.script_effects
