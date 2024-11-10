if type(_events_controller) ~= 'nil' then return _events_controller end

local udb = require('content_editor.database')

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

sdk.hook(
    sdk.find_type_definition('app.SuddenQuestEntity'):get_method('onEnd'),
    function (args)
        local this = sdk.to_managed_object(args[2])--[[@as app.SuddenQuestEntity]]
        if this == currentEntity then
            print('event end', this:get_Key())
            triggerChange(nil, currentEntity)
            currentEntity = nil
        end
    end
)

sdk.hook(
    sdk.find_type_definition('app.SuddenQuestEntity'):get_method('setup'),
    function (args)
        local this = sdk.to_managed_object(args[2])--[[@as app.SuddenQuestEntity]]
        print('event start', this:get_Key())
        if this ~= currentEntity then
            triggerChange(this, currentEntity)
            currentEntity = this
        end
    end
)

--- @param callback fun(currentEvent: Event|nil, previousEvent: Event|nil)
local function add_callback(callback)
    callbacks[#callbacks+1] = callback
end

_events_controller = {
    on_event_changed = add_callback,
}
return _events_controller