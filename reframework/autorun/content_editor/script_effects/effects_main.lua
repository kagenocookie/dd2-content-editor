if _userdata_DB == nil then _userdata_DB = {} end
if _userdata_DB.script_effects then return _userdata_DB.script_effects end

local udb = require('content_editor.database')
local utils = require('content_editor.utils')

--- @type table<string, ScriptEffectTypeDefinition>
local definitions = {}
local types = {}

--- @param definition ScriptEffectTypeDefinition
local function register_event_type(definition)
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

_G._userdata_DB._active_effects = active_effects

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

register_event_type({
    trigger_type = 'script',
    category = 'world',
    start = function (entity, ctx)
        local script = entity.data.start_script_id and udb.get_entity('custom_script', entity.data.start_script_id)
        if script then
            _userdata_DB.custom_scripts.try_execute(script)
        end
    end,
    stop = function (entity)
        local script = entity.data.stop_script_id and udb.get_entity('custom_script', entity.data.stop_script_id)
        if script then
            _userdata_DB.custom_scripts.try_execute(script)
        end
    end
})

_userdata_DB.script_effects = {
    add_effect_category = add_effect_category,
    register_event_type = register_event_type,
    get_effect_categories = get_effect_categories,
    get_event_types = get_event_types,

    start = start,
    stop = stop,
}

return _userdata_DB.script_effects
