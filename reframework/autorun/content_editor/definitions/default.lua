local common = require('content_editor.ui.common')

--- @type table<string, UserdataEditorSettings>
return {
    -- this one seems to have some magic that auto converts the via.GameObjectRef to a `nil|via.GameObject`
    -- not sure how we can edit this but it's probably a runtime entity that gets set automatically anyway
    ['via.GameObjectRef'] = {
        handler = common.readonly_label(),
    },
    ['via.GameObject'] = {
        force_expander = true,
    },
    ['via.UserData'] = {
        toString = function (value, context)
            return (context and context.data.classname or value:get_type_definition():get_full_name()) .. ': ' .. (value.get_Path and value:get_Path() or tostring(value))
        end
    },
    ['via.Quaternion'] = {
        force_expander = false,
    },
    ['via.Float4'] = {
        force_expander = false,
    },
    ['via.vec4'] = {
        force_expander = false,
    },
}
