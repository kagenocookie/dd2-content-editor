if _userdata_DB == nil then _userdata_DB = {} end
if _userdata_DB.script_effects then return _userdata_DB.script_effects end

local udb = require('content_editor.database')
local utils = require('content_editor.utils')

--- @type table<string, ScriptEffectTypeDefinition>
local definitions = {}
local types = {}

--- @param definition ScriptEffectTypeDefinition
local function register_effect_type(definition)
    if not definition[definition.trigger_type] then
        types[#types+1] = definition.trigger_type
    end
    definitions[definition.trigger_type] = definition
end

local function get_event_types()
    return types
end

local categories = {'world'}
local alwaysCategories = {['world'] = function () end}

--- @type table<integer, table<string, table[]>> {[effect_id] = {[context] = {data1, data2, ...}}}
local active_effects = {}

local _has_update_callback = false
local function start_update_callback()
    if _has_update_callback then return end
    _has_update_callback = true
    local last_update_time = os.clock()
    local TimeManager = sdk.get_managed_singleton('app.TimeManager') ---@type app.TimeManager
    re.on_application_entry('UpdateBehavior', function ()
        local time_now = os.clock()
        local delta = time_now - last_update_time
        last_update_time = time_now
        if TimeManager:get_IsTimeStop() then return end
        local stoppedEffects = {}
        for effectId, effectContexts in pairs(active_effects) do
            local effect = udb.get_entity('script_effect', effectId) --[[@as ScriptEffectEntity|nil]]
            -- "continue" please do you know it lua, please, let me continue
            if effect then
                local def = definitions[effect.trigger_type]
                if def.update then
                    for context, dataList in pairs(effectContexts) do
                        for _, data in ipairs(dataList) do
                            local success, shouldStop = pcall(def.update, effect, data, delta)
                            if not success or shouldStop == true then
                                stoppedEffects[#stoppedEffects+1] = {effect.id, context}
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

--- @param id integer
--- @param context table|REManagedObject|string A context object to link the event to so we can differentiate the same event being triggered on different objects
--- @param input_data any
local function start(id, context, input_data)
    if id == 0 then return end
    local effect = udb.get_entity('script_effect', id) --[[@as ScriptEffectEntity]]
    if not effect then
        print('ERROR: script effect ', id, 'not found')
        return
    end

    local trigger = definitions[effect.trigger_type]
    if trigger then
        local data = trigger.start(effect, input_data) or {}

        active_effects[id] = active_effects[id] or {}
        local effect_data = active_effects[id]

        effect_data[context] = effect_data[context] or {}
        effect_data[context][#effect_data[context]+1] = data
        if trigger.update then
            start_update_callback()
        end
    end
end

--- @param id integer
--- @param context table|REManagedObject|string The context object that was used to start the script effect initially
local function stop(id, context)
    local effect = udb.get_entity('script_effect', id) --[[@as ScriptEffectEntity]]
    if not effect then return end

    local effect_data = active_effects[id]
    local effect_context = effect_data and effect_data[context]
    if effect_context and #effect_context > 0 then
        local trigger = definitions[effect.trigger_type]
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
        print('WARNING: attempted to stop inactive script event', effect.trigger_type, id, effect_context)
    end
end

register_effect_type({
    trigger_type = 'script',
    category = 'world',
    start = function (entity, ctx)
        local script = entity.data.start_script_id and udb.get_entity('custom_script', entity.data.start_script_id)
        if script then
            local success, data = _userdata_DB.custom_scripts.try_execute(script, entity, ctx)
            if success then return data end
        end
    end,
    update = function (entity, data, deltaTime)
        local script = entity.data.update_script_id and udb.get_entity('custom_script', entity.data.update_script_id)
        if script then
            local success, shouldStop = _userdata_DB.custom_scripts.try_execute(script, entity, data, deltaTime)
            if not success or shouldStop then
                return true
            end
        end
    end,
    stop = function (entity)
        local script = entity.data.stop_script_id and udb.get_entity('custom_script', entity.data.stop_script_id)
        if script then
            _userdata_DB.custom_scripts.try_execute(script, entity, data)
        end
    end
})

_userdata_DB.script_effects = {
    add_effect_category = add_effect_category,
    register_effect_type = register_effect_type,
    get_effect_categories = get_effect_categories,
    get_event_types = get_event_types,

    start = start,
    stop = stop,
}

return _userdata_DB.script_effects
