if type(_scripted_events) ~= 'nil' then return _scripted_events end

local ctrl = require('event_editor.events_controller')
local effects = require('content_editor.script_effects.effects_main')

ctrl.on_event_changed(function (currentEvent, previousEvent)
    if previousEvent ~= nil then
        for _, effId in ipairs(previousEvent.scriptEffects or {}) do
            effects.stop(effId, previousEvent)
        end
    end
    if currentEvent ~= nil then
        for _, effId in ipairs(currentEvent.scriptEffects or {}) do
            effects.start(effId, currentEvent)
        end
    end
end)

_scripted_events = {}
return _scripted_events