if type(_events_controller) ~= 'nil' then return _events_controller end

local udb = require('content_editor.database')
local gamedb = require('event_editor.events_gamedata')
local helpers = require('content_editor.helpers')

local SuddenQuestManager = sdk.get_managed_singleton('app.SuddenQuestManager') ---@type app.SuddenQuestManager

--- @type app.SuddenQuestEntity|nil
local currentEntity = nil

--- @type fun(new: Event|nil, old: Event|nil)[]
local callbacks = {}

--- @param new app.SuddenQuestEntity|nil
--- @param old app.SuddenQuestEntity|nil
local function triggerChange(new, old)
    for _, callback in ipairs(callbacks) do
        callback(
            new and udb.get_entity('event', new:get_Key()) or nil,
            old and udb.get_entity('event', old:get_Key()) or nil
        )
    end
end

local function get_current_event_runtime_entity()
    return currentEntity or gamedb.get_current_runtime_entity()
end

local function get_current_event()
    if currentEntity then return udb.get_entity('event', currentEntity:get_Key()) end
    SuddenQuestManager = SuddenQuestManager or sdk.get_managed_singleton('app.SuddenQuestManager')
    local evt = SuddenQuestManager._CurrentEntity
    return evt and udb.get_entity('event', evt:get_Key())
end

--- @param callback fun(currentEvent: Event|nil, previousEvent: Event|nil)
local function add_callback(callback)
    callbacks[#callbacks+1] = callback
end

--- @param newEntity app.SuddenQuestEntity|nil
local function handleEventChanged(newEntity)
    if newEntity ~= currentEntity then
        -- print('event changed', currentEntity and currentEntity:get_Key(), '=>', newEntity and newEntity:get_Key())
        local prev = currentEntity
        currentEntity = newEntity
        triggerChange(newEntity, prev)
    end
end

sdk.hook(
    sdk.find_type_definition('app.SuddenQuestEntity'):get_method('onEnd'),
    function (args)
        local this = sdk.to_managed_object(args[2])--[[@as app.SuddenQuestEntity]]
        if this == currentEntity then
            handleEventChanged(nil)
        end
    end
)

sdk.hook(
    sdk.find_type_definition('app.SuddenQuestEntity'):get_method('setup'),
    function (args)
        handleEventChanged(sdk.to_managed_object(args[2])--[[@as app.SuddenQuestEntity]])
    end
)

helpers.hook_game_load_or_reset(function (ingame)
    if not ingame then
        handleEventChanged(nil)
    else
        local evt = get_current_event_runtime_entity()
        if evt then handleEventChanged(evt) end
    end
end)

udb.events.on('ready', function ()
    handleEventChanged(get_current_event_runtime_entity())
end)

_events_controller = {
    on_event_changed = add_callback,
    get_current = get_current_event,
    get_current_runtime_entity = get_current_event_runtime_entity,
    game = gamedb,
}
return _events_controller