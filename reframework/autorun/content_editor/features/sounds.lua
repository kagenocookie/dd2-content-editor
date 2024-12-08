if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._sounds then return usercontent._sounds end

local utils = require('content_editor.utils')

usercontent._sounds = {}

local t_soundcontainer = sdk.find_type_definition('app.WwiseContainerApp') or sdk.find_type_definition('soundlib.SoundContainer')
if t_soundcontainer then
    --- @generic T : function
    --- @param method REMethodDefinition
    --- @param callback fun(method: REMethodDefinition): T
    --- @return T|nil
    local function method_wrapper(method, callback)
        if method then return callback(method) end
    end

    usercontent._sounds.trigger_on_gameobject = method_wrapper(
        t_soundcontainer:get_method('triggerLogLess(System.UInt32, via.GameObject, via.GameObject)'),
        function (method)
            --- @param triggerId integer
            --- @param positionGameobject via.GameObject
            --- @param targetGameobject via.GameObject|nil
            return function (triggerId, positionGameobject, targetGameobject)
                method:call(utils.get_gameobject_component(positionGameobject, 'soundlib.SoundContainer'), triggerId, positionGameobject, targetGameobject)
            end
        end
    )

    local m_trigger_stop = t_soundcontainer:get_method('stopTriggered(System.UInt32, via.GameObject, System.UInt32)')
    if m_trigger_stop then
        function usercontent._sounds.stop_triggered(triggerId, targetGameobject)
            local soundcontainer = utils.get_gameobject_component(targetGameobject, 'soundlib.SoundContainer')--[[@as soundlib.SoundContainer]]
            if soundcontainer then
                m_trigger_stop:call(soundcontainer, triggerId, targetGameobject, 0)
            end
        end
    end
end

return usercontent._sounds