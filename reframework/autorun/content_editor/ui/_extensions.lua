local core = require('content_editor.core')
local utils = require('content_editor.utils')
local ui = require('content_editor.ui.imgui_wrappers')
local common = require('content_editor.ui.common')
local udb = require('content_editor.database')
local helpers = require('content_editor.helpers')

--- @param register_extension fun(type: string, handler: fun(handler: UIHandler, data: FieldExtension|table): UIHandler)
local function register(register_extension)
    register_extension('tooltip', function (handler, data)
        local text = data.text --- @type string
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            imgui.same_line()
            ui.tooltip(text)
            return changed
        end
    end)

    register_extension('conditional', function (handler, data)
        local condition = data.condition --- @type fun(ctx: UIContainer): boolean
        --- @type UIHandler
        return function (ctx)
            if condition(ctx) then
                local changed = handler(ctx)
                return changed
            end
            return false
        end
    end)

    register_extension('parent_field_conditional', function (handler, data)
        local field = data.field --- @type string
        local showValue = data.value --- @type any

        --- @type UIHandler
        return function (ctx)
            if ctx.parent.get()[field] == showValue then
                local changed = handler(ctx)
                return changed
            end
            return false
        end
    end)

    register_extension('object_explorer', function (handler)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            if imgui.tree_node('Object explorer') then
                object_explorer:handle_address(ctx.get())
                imgui.tree_pop()
            end
            return changed
        end
    end)

    register_extension('space_before', function (handler, data)
        local count = data.count or 1
        --- @type UIHandler
        return function (ctx)
            for _ = 1, count do
                imgui.spacing()
            end
            return handler(ctx)
        end
    end)

    register_extension('space_after', function (handler, data)
        local count = data.count or 1
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            for _ = 1, count do
                imgui.spacing()
            end
            return changed
        end
    end)

    register_extension('toggleable', function (handler, data)
        local inverted = data.inverted or false
        local field = data.field --- @type string

        return common.toggleable(
            handler,
            function (val) return val[field] == inverted end,
            function (ctx, toggle) ctx.get()[field] = (toggle == inverted) end,
            false
        )
    end)

    register_extension('sibling_field_toggleable', function (handler, data)
        local inverted = data.inverted or false
        local field = data.field --- @type string

        return common.toggleable(
            handler,
            function (val, ctx)
                local parent = ctx.parent and ctx.parent.get()
                return parent[field] == inverted
            end,
            function (ctx, toggle) ctx.parent.get()[field] = (toggle == inverted) end,
            false
        )
    end)

    register_extension('flag_toggleable', function (handler, data)
        local flagValue = data.flagValue --- @type integer
        local flagKey = data.flagKey --- @type string

        return common.toggleable(
            handler,
            function (val, ctx)
                local parent = ctx.parent and ctx.parent.get()
                return ((parent[flagKey] & flagValue) ~= 0)
            end,
            function (ctx, toggle)
                local parent = ctx.parent.get()
                if toggle then
                    parent[flagKey] = parent[flagKey] | flagValue
                else
                    parent[flagKey] = parent[flagKey] & (~flagValue)
                end
            end,
            true
        )
    end)

    register_extension('indent', function (handler, data)
        local indent = data.indent or 12
        --- @type UIHandler
        return function (ctx)
            imgui.indent(indent)
            local changed = handler(ctx)
            imgui.unindent(indent)
            return changed
        end
    end)

    register_extension('rect', function (handler, data)
        local size = data.size or 0
        --- @type UIHandler
        return function (ctx)
            imgui.begin_rect()
            local changed = handler(ctx)
            imgui.end_rect(size)
            return changed
        end
    end)

    register_extension('randomizable', function (handler, data)
        local get_random = data.randomizer --- @type fun(): any
        --- @type UIHandler
        return function (ctx)
            local changed = false
            local w = imgui.calc_item_width()
            if imgui.button('Randomize') then
                ctx.set(get_random())
                changed = true
            end
            imgui.set_next_item_width(w - 80)
            imgui.same_line()
            return handler(ctx) or changed
        end
    end)

    register_extension('filter', function (handler, data)
        local filter = data.filter --- @type fun(val: UIContainer): boolean
        --- @type UIHandler
        return function (ctx)
            if filter(ctx) then
                return handler(ctx)
            end
            return false
        end
    end)

    -- show a string input to write in the path to a userdata file or an option to create an independent non-native-file-linked one
    register_extension('userdata_picker', function (handler, data)
        local allowNew = data.allow_new == nil and true or data.allow_new --- @type boolean
        local classname = data.classname --- @type string|nil

        --- @type UIHandler
        return function (ctx)
            local value = ctx.get()
            if ctx.object ~= value then
                ctx.object = value
            end
            local changed
            if type(value) == 'string' then
                local newValue
                changed, newValue = imgui.input_text('Source file', value)
                if changed then
                    ctx.data._ref_userdata = nil
                    ctx.set(newValue)
                    value = newValue
                end
                ctx.data._ref_userdata = ctx.data._ref_userdata or sdk.create_userdata('app.AISituationTaskEntity', value)
                if ctx.data._ref_userdata and ui.treenode_tooltip('Data reference', "Preview of the object pointed to by the current path. Any changes will not get saved.") then
                    usercontent._ui_handlers.show_readonly(ctx.data._ref_userdata)
                    imgui.tree_pop()
                end
                if allowNew then
                    if imgui.button('Create new') then
                        ctx.set({})
                        ctx.data.userdata_picker = ''
                        changed = true
                    end
                    if ctx.data._ref_userdata then
                        imgui.same_line()
                        if imgui.button('Clone current') then
                            ctx.set(helpers.clone(ctx.data._ref_userdata, classname or ctx.data.classname, true))
                            ctx.data.userdata_picker = ''
                            ctx.data._ref_userdata = nil
                            changed = true
                        end
                    end
                end
            else
                local isRaw = type(value) ~= 'userdata'
                local currentPath = not isRaw and value:get_Path() or ''
                if currentPath ~= '' and imgui.tree_node(currentPath) then
                    if not ctx.data.userdata_picker then ctx.data.userdata_picker = currentPath end
                    _, ctx.data.userdata_picker = imgui.input_text('Change userdata source file', ctx.data.userdata_picker)
                    if ctx.data.userdata_picker and (value == nil or ctx.data.userdata_picker ~= currentPath) then
                        if imgui.button('Change file') then
                            local newData = sdk.create_userdata('via.UserData', ctx.data.userdata_picker)
                            if isRaw then
                                ctx.data._ref_userdata = newData
                                ctx.set(ctx.data.userdata_picker)
                                changed = true
                            else
                                ctx.set(newData)
                                changed = true
                            end
                        end
                    end
                    if allowNew then
                        if imgui.button('Create new') then
                            ctx.set(isRaw and {} or usercontent._ui_utils.create_instance(classname or ctx.data.classname))
                            ctx.data.userdata_picker = ''
                            changed = true
                        end
                        imgui.same_line()
                        if imgui.button('Clone current') then
                            ctx.set(helpers.clone(ctx.data._ref_userdata or value, classname or ctx.data.classname, isRaw))
                            ctx.data.userdata_picker = ''
                            changed = true
                        end
                    end
                    imgui.tree_pop()
                end
                imgui.spacing()
                changed = handler(ctx) or changed
            end
            return changed
        end
    end)

    -- let the user pick one of a preset list of userdata files with a dropdown
    register_extension('userdata_dropdown', function (handler, data)
        local options = data.options
        --- @type UIHandler
        return function (ctx)
            local value = ctx.get()
            if type(value) == 'string' then
                local changed, newPathIdx = imgui.combo('Source', utils.table_index_of(options, value), options)
                if changed and options[newPathIdx] ~= value then
                    value = options[newPathIdx]
                    ctx.set(value)
                    ctx.data._ref_userdata = nil
                else
                    changed = false
                end

                ctx.data._ref_userdata = ctx.data._ref_userdata or sdk.create_userdata('via.UserData', value)
                if ctx.data._ref_userdata and ui.treenode_tooltip('Data reference', "Preview of the object pointed to by the current path. Changes will not get saved.") then
                    usercontent._ui_handlers.show_readonly(ctx.data._ref_userdata)
                    imgui.tree_pop()
                end
                return changed
            else
                local current = value and value:get_Path() or ''
                local changed, newPathIdx = imgui.combo('Source', utils.table_index_of(options, current), options)
                if changed and options[newPathIdx] ~= current then
                    ctx.set(sdk.create_userdata('via.UserData', options[newPathIdx]))
                else
                    changed = false
                end

                imgui.spacing()
                if ui.treenode_tooltip('Data reference', "Preview of the object pointed to by the current path. Changes will not get saved.") then
                    handler(ctx)
                    imgui.tree_pop()
                end
                return changed
            end
        end
    end)

    register_extension('linked_entity', function (handler, data)
        local entity_type = data.entity_type --- @type string
        local draw_callback = data.draw ---@type fun(entity: DBEntity, context: UIContainer)
        local entity_getter = data.getter --- @type nil|fun(context: UIContainer): entity: DBEntity|nil, extra: any
        local labeler = data.labeler --- @type nil|fun(entity: DBEntity, context: UIContainer): string
        if not draw_callback then
            draw_callback = usercontent.ui.editor.get_entity_editor_func(entity_type)
        end

        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            local entity
            if entity_getter then
                entity = entity_getter(ctx)
            else
                entity = udb.get_entity(entity_type, ctx.get())
            end
            if not entity then
                local val = ctx.get()
                local id = type(val) == 'userdata' and val:ToString() or 'ID ' .. tostring(val)
                if val ~= data.ignoreId then
                    imgui.text_colored('Linked entity not found: ' .. entity_type .. ' (from  ' .. id .. ')', core.get_color('danger'))
                end
            else
                local label = labeler and labeler(entity, ctx) or 'Linked ' .. entity.type .. ' ' .. entity.id .. ': ' .. tostring(entity.label or usercontent.database.generate_entity_label(entity))
                imgui.push_style_color(0, core.get_color('info'))
                local show = imgui.tree_node(label)
                imgui.pop_style_color(1)
                if data.editorWindow then
                    imgui.same_line()
                    if imgui.button('Open in new window') then
                        usercontent.editor.open_editor_window(data.editorWindow, type(data.editorState) == 'function' and data.editorState(ctx) or data.editorState, entity_type, ctx.get())
                    end
                end
                if show then
                    draw_callback(entity, ctx)
                    imgui.tree_pop()
                end
            end
            return changed
        end
    end)

    local getter_settings = {is_readonly = true, hide_nonserialized = false, is_raw_data = false, allow_props = true, allow_methods = true}
    register_extension('getter_property', function (handler, data)
        local props = data.props or data.prop and {data.prop} --- @type string[]
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            imgui.spacing()
            for _, prop in ipairs(props) do
                local childCtx = ctx.children[prop]
                if childCtx == nil then
                    local getter = 'get_' .. prop
                    local propType = sdk.find_type_definition(ctx.data.classname):get_method(getter):get_return_type():get_full_name()
                    childCtx = usercontent._ui_handlers._internal.create_field_editor(
                        ctx,
                        ctx.data.classname,
                        getter,
                        propType,
                        prop .. '/Readonly',
                        usercontent._ui_handlers._internal.accessors.getter,
                        getter_settings)
                    childCtx.ui = usercontent._ui_handlers._internal.apply_overrides(childCtx.ui, ctx.data.classname, "__element", propType)
                end
                childCtx:ui()
            end
            return changed
        end
    end)

    local function cmd_try_load_and_execute(cmd, chunkname)
        local realcmd = cmd
        if not realcmd:find('return') then realcmd = 'return ' .. realcmd end

        local fn, err = load(realcmd, chunkname)
        if err or not fn then return false, (err or 'Failed to compile function') end

        local succ, result = pcall(fn)
        if not succ then return false, tostring(result) end
        return true, result
    end

    register_extension('methods', function (handler)
        local methodCount
        --- @type UIHandler
        return function (ctx)
            local target = ctx.get()
            if type(target) ~= 'userdata' or methodCount == 0 then return handler(ctx) end
            ---@cast target REManagedObject

            local minfo = usercontent._typecache.get_method_summary(ctx.data.classname)
            methodCount = #minfo
            if methodCount > 0 then imgui.begin_rect() end
            if methodCount > 0 and imgui.tree_node(ctx.label .. ' Methods') then
                local root_ctx = usercontent.ui.context.get_child(ctx, 'methods') or usercontent.ui.context.get_or_create_child(ctx, 'methods', {}, '', nil, '')
                root_ctx.data.filter = select(2, imgui.input_text('Filter', root_ctx.data.filter or ''))
                for i, methodinfo in ipairs(minfo) do
                    local ignore = false
                    if root_ctx.data.filter and root_ctx.data.filter ~= '' then
                        if not methodinfo.name:lower():find(root_ctx.data.filter:lower()) then
                            ignore = true
                        end
                    end
                    if not ignore and ui.treenode_suffix(methodinfo.name .. (methodinfo.method:is_static() and ' [static]' or '') .. '##' .. methodinfo.signature, methodinfo.signature:sub(#methodinfo.name + 1)) then
                        imgui.input_text('Signature', methodinfo.signature)
                        local paramcount = #methodinfo.params
                        local canExecute = true
                        local method_ctx = usercontent.ui.context.get_or_create_child(root_ctx, methodinfo.signature, {}, '', nil, '')

                        -- param inputs
                        if paramcount > 0 then
                            for p, param in ipairs(methodinfo.params) do
                                if param.is_simple_value then
                                    if method_ctx.object[p] == nil then
                                        method_ctx.object[p] = usercontent._ui_utils.create_instance(param.type)
                                    end
                                    usercontent._ui_handlers._internal.create_field_editor(method_ctx, '', p, param.type, p .. ': ' .. param.name, nil, ctx.data.ui_settings, true):ui()
                                else
                                    local inline_obj_key = p..'_obj'
                                    -- local meta = usercontent._typecache.get(param.type)
                                    if method_ctx.object[inline_obj_key] then
                                        usercontent._ui_handlers._internal.create_field_editor(method_ctx, '', p, param.type, p .. ': ' .. param.name .. ' (Temp object)', nil, ctx.data.ui_settings, false):ui()
                                        imgui.same_line()
                                        if imgui.button('Use script') then
                                            method_ctx.object[p] = ''
                                            method_ctx.object[inline_obj_key] = nil
                                        end
                                    else
                                        local changed, newvalue = ui.expanding_multiline_input(p .. ': ' .. param.name .. ' (Lua)', method_ctx.object[p] or '')
                                        if changed then method_ctx.object[p] = newvalue end
                                        if not method_ctx.object[p] then canExecute = false end

                                        imgui.same_line()
                                        if imgui.button('Create temp object') then
                                            -- method_ctx.object[inline_obj_key] = helpers.create_instance(param.type)
                                            -- method_ctx.object[p] = 'return sdk.to_managed_object(' .. method_ctx.object[inline_obj_key]:get_address() .. ')'
                                            method_ctx.object[inline_obj_key] = true
                                            method_ctx.object[p] = helpers.create_instance(param.type)
                                        end
                                    end
                                end
                            end
                        end

                        imgui.text('Return type: ' .. methodinfo.method:get_return_type():get_full_name())

                        if canExecute and imgui.button('Execute') then
                            method_ctx.object.last_error = nil
                            method_ctx.object.last_result = nil

                            -- collect call params
                            local args = {}
                            for p, param in ipairs(methodinfo.params) do
                                if param.is_simple_value or method_ctx.object[p .. '_obj'] or param.type == 'System.String' then
                                    args[#args+1] = method_ctx.object[p]
                                else
                                    local cmd = method_ctx.object[p]
                                    local succ, result = cmd_try_load_and_execute(cmd, '_method_exec_' .. methodinfo.signature)
                                    if succ then
                                        args[#args+1] = result
                                    else
                                        method_ctx.object.last_error = 'Arg ' .. i .. ': ' .. tostring(result)
                                        canExecute = false
                                        break
                                    end
                                end
                            end

                            -- if collected params were OK, execute now
                            if canExecute then
                                local success, execResult
                                print('Calling method', methodinfo.signature, table.unpack(args))
                                if methodinfo.method:is_static() then
                                    success, execResult = pcall(methodinfo.method.call, methodinfo.method, nil, table.unpack(args))
                                else
                                    success, execResult = pcall(methodinfo.method.call, methodinfo.method, target, table.unpack(args))
                                end
                                if not success then
                                    method_ctx.object.last_error = 'Execute error: ' .. tostring(execResult)
                                else
                                    if methodinfo.returntype == 'System.Void' then
                                        method_ctx.object.last_result = 'OK'
                                    else
                                        if type(execResult) == 'userdata' and execResult.add_ref then
                                            execResult = execResult:add_ref()
                                        elseif execResult == nil then
                                            execResult = 'null'
                                        end
                                        method_ctx.object.last_result = execResult
                                    end
                                end
                            end
                        end

                        if method_ctx.object.last_error ~= nil then
                            imgui.text_colored(method_ctx.object.last_error, core.get_color('error'))
                        elseif method_ctx.object.last_result ~= nil then
                            if type(method_ctx.object.last_result) == 'userdata' and method_ctx.object.last_result.get_type_definition then
                                usercontent._ui_handlers._internal.create_field_editor(method_ctx, '', 'last_result', method_ctx.object.last_result:get_type_definition():get_full_name(), 'Result', nil, ctx.data.ui_settings, true):ui()
                            else
                                imgui.text('Result: ' .. helpers.to_string(method_ctx.object.last_result, methodinfo.returntype))
                            end
                        end
                        imgui.tree_pop()
                    end
                end
                imgui.tree_pop()
            end
            if methodCount > 0 then imgui.end_rect(4) imgui.spacing() end
            return handler(ctx)
        end
    end)
    register_extension('props', function (handler)
        local meta
        --- @type UIHandler
        return function (ctx)
            local val = ctx.get()
            if type(val) ~= 'userdata' then return handler(ctx) end
            local containerType = ctx.data.classname

            meta = meta or usercontent._typecache.get(containerType--[[@as string]])
            if not meta.props or #meta.props == 0 then return handler(ctx) end

            imgui.begin_rect()
            if imgui.tree_node(ctx.label .. ' Properties') then
                imgui.same_line()
                if imgui.button('Refresh values') or ctx.data.props_autorefresh then
                    usercontent.ui.context.delete_children(ctx)
                end
                imgui.same_line()
                _, ctx.data.props_autorefresh = imgui.checkbox('Keep refreshing', ctx.data.props_autorefresh or false)

                for _, propdata in ipairs(meta.props) do
                    local prop = propdata[1]
                    local propkey = '__prop_' .. prop
                    local childCtx = ctx.children[propkey]
                    if not childCtx then
                        local propTypeName = propdata[2]
                        local methods = propdata[3]
                        childCtx = usercontent._ui_handlers._internal.create_field_editor(
                            ctx,
                            ctx.data.classname,
                            propkey,
                            propTypeName,
                            usercontent._ui_handlers._internal.generate_field_label(prop, true),
                            usercontent._ui_handlers._internal.accessors.create_prop(sdk.find_type_definition(containerType), (methods & 1) ~= 0 and ('get_' .. prop), (methods & 2) ~= 0 and ('set_' .. prop)),
                            getter_settings)

                        local org_ui = childCtx.ui
                        ---@cast org_ui -nil
                        childCtx.ui = function (context)
                            if context.data._propError then
                                imgui.text(context.label .. ': ')
                                imgui.same_line()
                                imgui.text_colored(context.data._propError, core.get_color('error'))
                                return false
                            end

                            local propval = context.get()
                            if propval == usercontent.ui.handlers._internal.prop_invalid_error_value_constant then
                                context.data._propError = propval.message
                                imgui.text(context.label .. ': ')
                                imgui.same_line()
                                imgui.text_colored(context.data._propError, core.get_color('error'))
                                return false
                            end
                            return org_ui(context)
                        end
                    end
                    childCtx:ui()
                end
                imgui.tree_pop()
            end
            imgui.end_rect(4)
            imgui.spacing()
            return handler(ctx)
        end
    end)

    local t_transformObj = sdk.find_type_definition('via.gui.TransformObject')
    register_extension('gui_tree', function (handler)
        --- @type UIHandler
        return function (ctx)
            local gui = ctx.get() ---@type via.gui.PlayObject|nil
            if not gui then return handler(ctx) end

            ctx.data.gui_path = ctx.data.gui_path or utils.gui.get_path(gui)
            if ctx.data.gui_path ~= ctx.label then
                imgui.input_text('Full GUI path', ctx.data.gui_path)
            end

            if ctx.data.is_transform == nil then
                ctx.data.is_transform = gui:get_type_definition():is_a(t_transformObj)
            end
            if ctx.data.is_transform then
                imgui.begin_rect()
                imgui.push_id(gui:get_address())
                if imgui.tree_node('GUI Children') then
                    local gui_child_ctx, isnew = usercontent.ui.context.get_or_create_child(ctx, 'gui_children', {}, '', nil, '')
                    if isnew then
                        local create_field_editor = usercontent.ui.handlers._internal.create_field_editor
                        local child = gui:get_Child()
                        while child do
                            local index = #gui_child_ctx.object + 1
                            gui_child_ctx.object[index] = child:add_ref()
                            create_field_editor(gui_child_ctx, '__none', index, child:get_type_definition():get_full_name(), child:get_Name(), nil, ctx.data.ui_settings, false)
                            child = child:get_Next()
                        end
                    end

                    for _, guiChild in ipairs(gui_child_ctx.children) do
                        guiChild:ui()
                    end
                    imgui.tree_pop()
                end
                imgui.pop_id()
                imgui.end_rect(4)
                imgui.spacing()
            end
            local changed = handler(ctx)
            return changed
        end
    end)

    local MessageManager = sdk.get_managed_singleton('app.MessageManager')
    register_extension('translate_guid', function (handler, data)
        local prefix = data.data or ''
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            local guid = ctx.get() --- @type System.Guid
            if guid.mData1 ~= 0 or guid.mData2 ~= 0 or guid.mData3 ~= 0 or guid.mData4L ~= 0 then
                local msg = MessageManager:getMessage(guid)
                imgui.text_colored(prefix .. (msg ~= '' and msg or '<unknown message>'), core.get_color('info'))
            end
            return changed
        end
    end)

    local nil_setter = function () end
    register_extension('readonly', function (handler, data)
        local text = data.text or 'Field is read only'
        --- @type UIHandler
        return function (ctx)
            if not ctx.set ~= nil_setter then
                ctx.set = nil_setter
            end
            imgui.text_colored('*', core.get_color('info'))
            if imgui.is_item_hovered() then
                imgui.set_tooltip(text)
            end
            imgui.same_line()
            handler(ctx)
            return false
        end
    end)

    register_extension('handler_pre', function (handler, data)
        local custom_handler = data.handler --- @type fun(ctx: UIContainer): nil
        if not custom_handler then return handler end

        --- @type UIHandler
        return function (ctx)
            custom_handler(ctx)
            return handler(ctx)
        end
    end)

    register_extension('handler_post', function (handler, data)
        local custom_handler = data.handler --- @type fun(ctx: UIContainer, changed: boolean): nil
        if not custom_handler then return handler end

        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            custom_handler(ctx, changed)
            return changed
        end
    end)

    register_extension('autotranslate', function (handler)
        local translations
        --- @type UIHandler
        return function (ctx)
            if not translations then translations = usercontent.ui.translation end
            if not ctx.data.autotranslation then
                if translations then
                    local text = ctx.get()
                    if ctx.data.classname == 'System.Guid' then
                        local msgText = MessageManager:getMessage(text)
                        if msgText and msgText ~= '' then
                            text = msgText
                        else
                            text = translations.translate('message_not_found_guid', 'editor')
                        end
                    end
                    ctx.data.autotranslation = translations.translate_t('auto_translation', 'editor', { text = translations.per_word_translate(text) })
                else
                    ctx.data.autotranslation = ''
                end
            end

            local changed = handler(ctx)
            if ctx.data.autotranslation ~= '' then
                imgui.text_colored(tostring(ctx.data.autotranslation), core.get_color('info'))

                ui.tooltip(translations.translate('auto_translation_tooltip', 'editor'))
                imgui.same_line()
                if imgui.button('Refresh translation') then
                    ctx.data.autotranslation = nil
                end
            end
            return changed
        end
    end)

    register_extension('button', function (handler, data)
        local action = data.action ---@type fun(ctx: UIContainer): boolean|nil
        local label = data.label or 'Action'
        if not action then return handler end
        local tooltip = data.tooltip ---@type string

        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            if imgui.button(label) then
                changed = action(ctx) or changed
            end
            if tooltip and imgui.is_item_hovered() then
                imgui.set_tooltip(tooltip)
            end
            return changed
        end
    end)

end

return register