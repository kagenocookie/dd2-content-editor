if usercontent == nil then usercontent = {} end
if usercontent.custom_scripts then return usercontent.custom_scripts end

local udb = require('content_editor.database')
local core = require('content_editor.core')
local type_definitions = require('content_editor.definitions')

--- @class CustomScriptEntity : DBEntity
--- @field script string
--- @field hook_type string
--- @field script_func fun(args: any[], script_args: any)|nil
--- @field __tempScriptChange string|nil

--- @class CustomScriptData : EntityImportData
--- @field script string
--- @field hook_type string

local function preprocess_func(funcStr)
    return 'local input = {...}\n' .. funcStr
end

udb.register_entity_type('custom_script', {
    export = function (instance)
        --- @cast instance CustomScriptEntity
        return { script = instance.script, hook_type = instance.hook_type }
    end,
    import = function (data, instance)
        --- @cast data CustomScriptEntity|nil
        --- @cast instance CustomScriptEntity|nil
        instance = instance or {}
        instance.script = data and data.script or ''
        instance.hook_type = data and data.hook_type or ''
        instance.script_func = load(preprocess_func(instance.script), data and ('_custom_script_' .. data.id) or nil, 't')
        return instance
    end,
    insert_id_range = {100000, 99999900},
    delete = function () return 'ok' end,
    root_types = {},
})

--- @param script CustomScriptEntity
--- @return boolean success, any result
local function try_execute_script(script, ...)
    local success, result = pcall(script.script_func, ...)
    return success, result
end

--- Define a custom script hook
--- @param classname string
--- @param method string
--- @param script_id_fetcher fun(args: any[]): id: integer|nil, script_args: any
local function define_script_hook(classname, method, script_id_fetcher)
    sdk.hook(
        sdk.find_type_definition(classname):get_method(method),
        function (args)
            local scriptId, script_args = script_id_fetcher(args)
            if scriptId and scriptId ~= -1 then
                local script = udb.get_entity('custom_script', scriptId)
                if script and script.script_func then
                    local success, result = pcall(script.script_func, args, script_args)
                    if success then
                        thread.get_hook_storage().result = result
                    else
                        print('ERROR in custom script ' .. script.label, result)
                        thread.get_hook_storage().result = false
                    end
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end,
        function (ret)
            local overrideResult = thread.get_hook_storage().result
            if overrideResult then
                return sdk.to_ptr(overrideResult)
            end
            return ret
        end
    )
end

--- @param classname string
--- @param script_id_fetcher fun(target: any): integer|nil
--- @param make_script_hook fun(target: any, hook: boolean) Function that should change the target object in a way that it will be considered a script hook one
--- @param set_id fun(target: any, id: integer) Set the script ID on the hooked object
--- @param helpstring nil|string Text to be displayed with the editor to help the user
--- @param show_default_editor nil|boolean Whether to keep showing the default editor even with a script override set
local function define_script_hook_editor_override(classname, script_id_fetcher, make_script_hook, set_id, helpstring, show_default_editor)
    local prevOvrs = type_definitions.get(classname)
    local extensions = prevOvrs.extensions or {}
    -- prepend the extenion to whatever existing extensions may be defined for the class
    table.insert(extensions, 1, { type = 'custom_script_hookable', id_fetcher = script_id_fetcher, change_to_hook = make_script_hook, set_id = set_id, helpstring = helpstring, show_default_editor = show_default_editor })
    type_definitions.override('', {
        [classname] = {
            extensions = extensions
        }
    })
end

usercontent.custom_scripts = {
    define_script_hook = define_script_hook,
    define_script_hook_editor_override = define_script_hook_editor_override,
    try_execute = try_execute_script,
}

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local helpers = require('content_editor.helpers')
    local ui = require('content_editor.ui')

    ui.handlers.register_extension('custom_script_hookable', function (handler, data)
        local id_fetcher = data.id_fetcher ---@type fun(args: any): integer|nil
        local change_to_hook = data.change_to_hook ---@type fun(value: any, hook: boolean)
        local set_id = data.set_id ---@type fun(value: any, id: integer)
        local helpstring = data.helpstring ---@type string|nil
        local show_default_editor = data.show_default_editor or false --- @type boolean

        --- @type UIHandler
        return function (ctx)
            local changed = false
            local val = ctx.get()
            local scriptId = id_fetcher(ctx.get())
            if scriptId and scriptId > 0 then
                if imgui.button('Use vanilla logic') then
                    change_to_hook(val, false)
                    changed = true
                end
                if not ctx.data._selected_entity then
                    ui.editor.set_selected_entity_picker_entity(ctx.data, 'custom_script', udb.get_entity('custom_script', scriptId))
                end
                local script = ui.editor.entity_picker('custom_script', ctx.data, nil, 'Script')
                if script and script.id ~= scriptId then
                    set_id(val, script.id)
                    changed = true
                end
                --- @cast script CustomScriptEntity|nil
                if script then
                    imgui.indent(8)
                    usercontent.custom_scripts.draw_script_editor(script)
                    if helpstring then imgui.text_colored(helpstring, core.get_color('info')) end
                    imgui.unindent(8)
                else
                    imgui.text_colored('Script not found, ID ' .. scriptId, core.get_color('warning'))
                    if editor.active_bundle and imgui.button('Create##script') then
                        local ent = udb.insert_new_entity('custom_script', editor.active_bundle, { })
                        if ent then
                            set_id(val, ent.id)
                            ui.editor.set_selected_entity_picker_entity(ctx.data, 'custom_script', ent)
                        end
                    end
                end

                if show_default_editor then
                    changed = changed or handler(ctx)
                end

                return changed
            else
                if imgui.button('Use custom script') then
                    change_to_hook(val, true)
                    changed = true
                end
                return changed or handler(ctx)
            end
        end
    end)

    local curScriptData = {}

    --- @param script CustomScriptEntity
    ui.editor.set_entity_editor('custom_script', function (script)
        local tempData = curScriptData[script]
        if not tempData then
            tempData = {}
            -- note, we're never removing these so it would leak memory if someone happens to create and remove a lot of scripts
            -- probably irrelevant, ignore for now
            curScriptData[script] = tempData
        end
        local entityChanged = false

        local changed, newscript = imgui.input_text_multiline('Script', script.__tempScriptChange or script.script, 500)
        if changed then script.__tempScriptChange = newscript end
        if script.__tempScriptChange and script.__tempScriptChange ~= script.script then
            if imgui.button('Confirm change') then
                local compiledFunc = load(preprocess_func(script.__tempScriptChange))
                if compiledFunc then
                    script.script = script.__tempScriptChange
                    script.script_func = compiledFunc
                    script.__tempScriptChange = nil
                    udb.mark_entity_dirty(script)
                    entityChanged = true
                else
                    tempData.lastExecResultSuccess = false
                    tempData.lastExecResult = 'Compilation failed'
                end
            end
            imgui.same_line()
            if imgui.button('Revert') then
                script.__tempScriptChange = nil
            end
        end

        if script.script_func and not script.__tempScriptChange and (imgui.button('Try executing') or tempData.forceExecute) then
            local success, result = pcall(script.script_func)
            tempData.lastExecResultSuccess = success
            tempData.lastExecResult = result
        end
        imgui.same_line()
        tempData.forceExecute = select(2, imgui.checkbox('Continuously execute', tempData.forceExecute or false))

        if tempData.lastExecResultSuccess ~= nil then
            if tempData.lastExecResultSuccess then
                imgui.text_colored('Script executed successfully:', core.get_color('success'))
            else
                imgui.text_colored('Script failed to execute: ', core.get_color('error'))
            end
            imgui.text(helpers.to_string(tempData.lastExecResult))
        end

        return entityChanged
    end)

    editor.define_window('scripts', 'Scripts', function (state)
        local selectedItem = ui.editor.entity_picker('custom_script', state)
        if editor.active_bundle and imgui.button('Create new script') then
            local newScript = udb.insert_new_entity('custom_script', editor.active_bundle)
            ui.editor.set_selected_entity_picker_entity(state, 'custom_script', newScript)
        end

        if selectedItem then
            --- @cast selectedItem CustomScriptEntity
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_editor(selectedItem, state)
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
        end
    end)

    editor.add_editor_tab('scripts')
end

return usercontent.custom_scripts
