local common = require('content_editor.ui.common')

--- @type table<string, UserdataEditorSettings>
return {
    -- this one seems to have some magic that auto converts the via.GameObjectRef to a `nil|via.GameObject`
    -- not sure how we can edit this but it's probably a runtime entity that gets set automatically anyway
    ['via.GameObjectRef'] = {
        handler = common.readonly_label(),
    },
    ['via.UserData'] = {
        toString = function (value, context)
            return (context and context.data.classname or value:get_type_definition():get_full_name()) .. ': ' .. (value.get_Path and value:get_Path() or tostring(value))
        end
    },
    ['via.Quaternion'] = {
        force_expander = false,
    },
    ['app.PrefabController'] = {
        import_handler = {
            export = function (src)
                if not src or not src._Item then return '' end
                return src._Item:get_Path()
            end,
            import = function (src, target)
                if src == nil or src == '' or src == 'null' then return nil end
                target = target or sdk.create_instance('app.PrefabController')
                target._Item = target._Item or sdk.create_instance('via.Prefab') ---@type via.Prefab
                target._Item:set_Path(src)
                return target
            end
        }
    },
}
